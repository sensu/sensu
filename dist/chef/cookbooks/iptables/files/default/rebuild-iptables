#!/usr/bin/perl -w
our $ID = q$Id: rebuild-iptables 344 2006-10-04 02:48:30Z digant $;

#
# rebuild-iptables -- Construct an iptables rules file from fragments.
#
# Written by Russ Allbery <rra@stanford.edu>
# Adapted by Digant C Kasundra <digant@stanford.edu>
# Adapted by Joe Williams (2011) <joe@joetify.com>
# Copyright 2005, 2006 Board of Trustees, Leland Stanford Jr. University
#
# Constructs an iptables rules file from the prefix, standard, and suffix
# files in the iptables configuration area, adding any additional modules
# specified in the command line, and prints the resulting iptables rules to
# standard output (suitable for saving into /var/lib/iptables or some other
# appropriate location on the system).

##############################################################################
# Modules and declarations
##############################################################################

require 5.006;
use strict;

use Getopt::Long qw(GetOptions);

# Path to the iptables template area.
our $TEMPLATE = '/etc/iptables.d';

##############################################################################
# Installation
##############################################################################

# Return the prefix
sub prefix {
  my $data;
  ( $data = <<'END_OF_PREFIX' ) =~ s/^\s+//gm;
        *filter
        :INPUT ACCEPT
    :FORWARD ACCEPT
    :OUTPUT ACCEPT
    :FWR -
    -A INPUT -j FWR
    -A FWR -i lo -j ACCEPT
END_OF_PREFIX

  return $data;
}

# Return the suffix
sub suffix {
  my $data;
  ( $data = <<'END_OF_SUFFIX' ) =~ s/^\s+//gm;
        # Rejects all remaining connections with port-unreachable errors.

        -A FWR -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j REJECT --reject-with icmp-port-unreachable
        -A FWR -p udp -j REJECT --reject-with icmp-port-unreachable
        COMMIT
END_OF_SUFFIX

  return $data;
}

sub snat {
  my $data = "";
  if ( -f "/etc/iptables.snat" ) {
    open( SNAT, "<", "/etc/iptables.snat" )
      or die "$0: cannot open /etc/iptables.snat: $!\n";
    while (<SNAT>) {
      $data = $data . $_;
    }
    close(SNAT);
  }
  return $data;
}

# Read in a file, processing includes as required.  Returns the contents of
# the file as an array.
sub read_iptables {
  my ($file) = @_;
  my @data;
  $file = $TEMPLATE . '/' . $file unless $file =~ m%^\.?/%;
  local *MODULE;
  open( MODULE, '<', $file ) or die "$0: cannot open $file: $!\n";
  local $_;
  while (<MODULE>) {
    if (/^\s*include\s+(\S+)$/) {
      my $included = $1;
      $included = $TEMPLATE . '/' . $included
        unless $included =~ m%^\.?/%;
      if ( $file eq $included ) {
        die "$0: include loop in $file, line $.\n";
      }
      push( @data, "\n" );
      push( @data, read_iptables($included) );
      push( @data, "\n" );
    } elsif (/^\s*include\s/) {
      die "$0: malformed include line in $file, line $.\n";
    } else {
      push( @data, $_ );
    }
  }
  close MODULE;
  return @data;
}

# Write a file carefully.
sub write_iptables {
  my ( $file, @data ) = @_;
  open( NEW, "> $file.new" ) or die "$0: cannot create $file.new: $!\n";
  print NEW @data or die "$0: cannot write to $file.new: $!\n";
  close NEW       or die "$0: cannot flush $file.new: $!\n";
  rename( "$file.new", $file )
    or die "$0: cannot install new $file: $!\n";
}

# Install iptables on a Red Hat system.  Takes the array containing the new
# iptables data.
sub install_redhat {
  my (@data) = @_;
  write_iptables( '/etc/sysconfig/iptables', @data );
  system( "/sbin/service", "iptables", "restart" );
}

# Install iptables on a Debian system.  Take the array containing the new
# iptables data.
sub install_debian {
  my (@data) = @_;
  unless ( -d '/etc/iptables' ) {
    mkdir( '/etc/iptables', 0755 )
      or die "$0: cannot mkdir /etc/iptables: $!\n";
  }
  write_iptables( "/etc/iptables/general", @data );
  system("/sbin/iptables-restore < /etc/iptables/general") == 0
    or die "rebuild-iptables: iptables-restore failed! - $?"
}

##############################################################################
# Main routine
##############################################################################

# Fix things up for error reporting.
$| = 1;
my $fullpath = $0;
$0 =~ s%.*/%%;

# Parse command-line options.
my ( $help, $version );
Getopt::Long::config( 'bundling', 'no_ignore_case' );
GetOptions(
  'h|help'    => \$help,
  'v|version' => \$version
) or exit 1;
if ($help) {
  print "Feeding myself to perldoc, please wait....\n";
  exec( 'perldoc', '-t', $fullpath );
} elsif ($version) {
  my $version = join( ' ', ( split( ' ', $ID ) )[ 1 .. 3 ] );
  $version =~ s/,v\b//;
  $version =~ s/(\S+)$/($1)/;
  $version =~ tr%/%-%;
  print $version, "\n";
  exit;
}
my @modules;

if ( -d '/etc/iptables.d' ) {
  @modules = </etc/iptables.d/*>;
}

# Concatenate everything together.
my @data;
push( @data, prefix() );
push( @data, "\n" );
for my $module (@modules) {
  push( @data, read_iptables($module) );
  push( @data, "\n" );
}
push( @data, suffix() );
push( @data, snat() );

if ( -f '/etc/debian_version' ) {
  install_debian(@data);
} elsif ( -f '/etc/redhat-release' ) {
  install_redhat(@data);
} else {
  die "$0: cannot figure out whether this is Red Hat or Debian\n";
}

exit 0;
__END__

##############################################################################
# Documentation
##############################################################################

=head1 NAME

rebuild-iptables - Construct an iptables rules file from fragments

=head1 SYNOPSIS

rebuild-iptables [B<-hv>]

=head1 DESCRIPTION

B<rebuild-iptables> constructs an iptables configuration file by concatenating
various modules found in F</etc/iptables.d>.  The resulting iptables
configuration file is written to the appropriate file for either Red Hat or
Debian (determined automatically) and iptables is restarted.

Each module is just a text file located in the directory mentioned above that
contains one or more iptables configuration lines (basically the arguments to
an B<iptables> invocation), possibly including comments.

Along with the modules in the directory specified, a standard prefix and suffix
is added.

Normally, the contents of each module are read in verbatim, but a module may
also contain the directive:

    include <module>

on a separate line, where <module> is the path to another module to include,
specified the same way as modules given on the command line (hence, either a
file name relative to F</afs/ir/service/jumpstart/data/iptables> or an
absolute path).  Such a line will be replaced with the contents of the named
file.  Be careful when using this directive to not create loops; files
including themselves will be detected, but more complex loops will not and
will result in infinite output.

=head1 OPTIONS

=over 4

=item B<-h>, B<--help>

Print out this documentation (which is done simply by feeding the script to
C<perldoc -t>).

=item B<-v>, B<--version>

Print out the version of B<rebuild-iptables> and exit.

=back

=head1 FILES

=over 4

=item F</etc/iptables.d>

The default module location.

=item F</etc/debian_version>

If this file exists, the system is assumed to be a Debian system for
determining the installation location when B<-i> is used.

=item F</etc/iptables/general>

The install location of the generated configuration file on Debian.

=item F</etc/redhat-release>

If this file exists, the system is assumed to be a Red Hat system for
determining the installation location when B<-i> is used.

=item F</etc/sysconfig/iptables>

The install location of the generated configuration file on Red Hat.

=back

=head1 AUTHOR

Russ Allbery <rra@stanford.edu>
Digant C Kasundra <digant@stanford.edu>

=head1 SEE ALSO

iptables(8)

=cut
