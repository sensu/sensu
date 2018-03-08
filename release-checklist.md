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
release tag using the Sensu Ruby gem version and a build iteration
(vX.X.X-X)

2. Push the release tag to trigger package builds on Travis CI (pushed
to S3 bucket)
