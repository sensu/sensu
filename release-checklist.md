## Release Checklist

### Ruby Gem

1. Ensure relevant pull-requests have been merged

2. Update CHANGELOG to reflect all changes and set the release date ("X.X.X - 20XX-XX-XX")

3. Bump the VERSION of Sensu in `lib/sensu/constants.rb`

4. Commit the CHANGELOG and VERSION changes ("major|minor|patch version bump, X.X.X")

5. Release the "sensu" Ruby gem: `bundle exec rake release` (need signature private key)
