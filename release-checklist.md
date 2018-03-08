## Release Checklist

### Ruby Gem

1. Ensure relevant pull-requests have been merged

2. Update CHANGELOG to reflect all changes and set the release date
("X.X.X - 20XX-XX-XX")

3. Bump the VERSION of Sensu in `lib/sensu/constants.rb`

4. Commit the CHANGELOG and VERSION changes ("major|minor|patch
version bump, X.X.X")

5. Release the "sensu" Ruby gem: `bundle exec rake release` (need gem
signature private key)

### Packages

1. Create a [sensu-omnibus](https://github.com/sensu/sensu-omnibus)
[release tag](#release-tagging) using the Sensu Ruby gem version and a
build iteration (vX.X.X-X)

2. Push the release tag to trigger package builds on Travis CI (pushed
to S3 bucket)

### Release Tagging

A [sensu-omnibus](https://github.com/sensu/sensu-omnibus) release tag
must have a "v" prefix and use a dash (-) to join the Sensu version
with the build iteration. For example, the second build iteration of
Sensu version 1.0.1 would be tagged as `v1.0.1-2`.

### Publishing

The Sensu 1.X package build pipeline pushes package builds (deb, rpm,
etc) to an Amazon S3 bucket. The Sensu 1.x package repositories live
on core.sensuapp.com, which are fronted by the Fastly CDN
(repositories.sensuapp.org). The package repositories have two
channels, "unstable" and "main" (or "stable"), which are managed by
tooling on core.sensuapp.com (pulls package versions from the S3
bucket). This tooling is managed by the Sensu Inc Engineering team.

All packages get published to the repository "unstable" channel prior
to promotion to the "main" channel. How long a package resides in the
"unstable" channel before promotion depends on the SemVer version
change (e.g. patch level). A package for a patch level bump typically
resides in "unstable" for 3-5 days, whereas its 5-14 days for a minor
version bump.
