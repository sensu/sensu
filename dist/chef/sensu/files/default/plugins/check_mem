#!/bin/bash
#
# evaluate free system memory from Linux based systems
#
# Date: 2007-11-12
# Author: Thomas Borger - ESG
#
# the memory check is done with following command line:
# free -m | grep buffers/cache | awk '{ print $4 }'

# get arguments

while getopts 'w:c:hp' OPT; do
  case $OPT in
    w)  int_warn=$OPTARG;;
    c)  int_crit=$OPTARG;;
    h)  hlp="yes";;
    p)  perform="yes";;
    *)  unknown="yes";;
  esac
done

# usage
HELP="
    usage: $0 [ -w value -c value -p -h ]

    syntax:

            -w --> Warning integer value
            -c --> Critical integer value
            -p --> print out performance data
            -h --> print this help screen
"

if [ "$hlp" = "yes" -o $# -lt 1 ]; then
  echo "$HELP"
  exit 0
fi

# get free memory
FMEM=`free -m | grep buffers/cache | awk '{ print $4 }'`

# output with or without performance data
if [ "$perform" = "yes" ]; then
  OUTPUTP="free system memory: $FMEM MB | free memory="$FMEM"MB;$int_warn;$int_crit;0"
else
  OUTPUT="free system memory: $FMEM MB"
fi

if [ -n "$int_warn" -a -n "$int_crit" ]; then

  err=0

  if (( $FMEM <= $int_warn )); then
    err=1
  elif (( $FMEM <= $int_crit )); then
    err=2
  fi

  if (( $err == 0 )); then

    if [ "$perform" = "yes" ]; then
      echo "MEM OK - $OUTPUTP"
      exit "$err"
    else
      echo "MEM OK - $OUTPUT"
      exit "$err"
    fi

  elif (( $err == 1 )); then
    if [ "$perform" = "yes" ]; then
      echo "MEM WARNING - $OUTPUTP"
      exit "$err"
    else
      echo "MEM WARNING - $OUTOUT"
      exit "$err"
    fi

  elif (( $err == 2 )); then

    if [ "$perform" = "yes" ]; then
      echo "MEM CRITICAL - $OUTPUTP"
      exit "$err"
    else
      echo "MEM CRITICAL - $OUTPUT"
      exit "$err"
    fi

  fi

else

  echo "no output from plugin"
  exit 3

fi
exit
