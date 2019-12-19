# Change Log
This project adheres to [Semantic Versioning](http://semver.org/).

This CHANGELOG follows the format listed [here](https://github.com/sensu-plugins/community/blob/master/HOW_WE_CHANGELOG.md)

## [Unreleased]

## [1.9.0] - 2019-12-18

### Fixed
- Fixed check subdue times resolution, now including nanoseconds.
- API 204 no content responses now return a nil body.
- Fixed Travis CI testing (RabbitMQ was missing on Xenial).

### Added
- Added support for discarding oversized transport messages to protect
Sensu, e.g. {"sensu":{"server": {"max_message_size": 2097152}}}.

## [1.8.0] - 2019-07-09

### Added
- The sensu-server results and keepalives Sensu Transport pipes are now
configurable. These values should only be set/changed when creating
active-active Sensu deployments, leveraging the RabbitMQ shovel	plugin for
cross site check result and keepalive replication.

## [1.7.1] - 2019-07-08

### Fixed
- Now using sensu-transport 8.3.0 which will trigger a reconnect when trying to publish to RabbitMQ when in a disconnected state.
- Use `--no-document` when installing gems via `sensu-install` instead of deprecated `--no-ri --no-rdoc`.

## [1.7.0] - 2019-02-19

### Added
- Added a response body to the api health endpoint including transport consumer & message counts.
- Bump sensu-extensions to 1.11.0 to add support for built-in sensu-extensions-deregistration handler.
- Added an eventmachine globbal catch-all error handler.

### Fixed
- Token substitution will now only split on the first instance of the pipe character.
- Use `deep_dup` in api token substitution to prevent an issue where substitution could use an incorrect value.
- Redacted attributes are now redacted from the `/clients` and `/clients/:client` routes.
- Server registry entires that fail to expire are now cleaned up.
- Improved error logging.

## [1.6.2] - 2018-12-07

### Fixed
- Fixed Redis Sentinel DNS resolution error handling. Sentinel DNS
hostname resolution is now done upfront, an IP address is provided to
EventMachine.

## [1.6.1] - 2018-10-23

### Fixed
- Now using sensu-transport 8.2.0 which fixes an issue where Sensu would freeze when trying to reconnect to RabbitMQ.

## [1.6.0] - 2018-10-12

### Fixed
- Now using EventMachine version 1.2.7 to allow newer compiler versions to build this project.

### Added
- Add additional sensitive information to default redaction list.
- Added API DELETE /check/:check_name that will deletes all results & history for a given check name.

### Changed
- Replace proxy check result commands with their original definition value.
- Now using sensu-transport 8.1.0 to use separate RabbitMQ transport connections for improved flow control.

## [1.5.0] - 2018-09-04

### Fixed
- Bumped sensu-extensions to version 1.10.0 to include subscription support in the check dependencies filter.
- Improved check result validation by applying existing validation rules from sensu-settings to check results created using the API and the client socket.

## [1.4.3] - 2018-07-23

### Fixed
- Prevent check results from being published with an empty source attribute.
- Use handler extension definitions when logging rather than handler extension objects.
- Added validation for ttl attribute in results API.
- Fixed case where proxy checks with token substitution can retain previous values.

## [1.4.2] - 2018-05-10

### Fixed
- Fixed API GET /results, results were incorrectly reported under a single client name.

## [1.4.1] - 2018-05-04

### Fixed
- Include em-http-request Ruby gem in runtime dependencies.

## [1.4.0] - 2018-05-02

### Added
- Sensu call-home mechanism, the Tessen client (opt-in). It sends anonymized data about the Sensu installation to the Tessen hosted service (Sensu Inc), on sensu-server startup and every 6 hours thereafter. All data reports are logged for transparency/awareness and transmitted over HTTPS. The anonymized data currently includes the flavour of Sensu (Core or Enterprise), the Sensu version, and the Sensu client and server counts.
- API list endpoints (e.g. /events) now all support pagination.

### Changed
- Support for writing multiple check results to the client socket (in one payload).
- Improved event last_ok, now updating the value when storing latest check results for better accuracy.

### Fixed
- Include child process (e.g. check execution) stop (SIGTERM/KILL) error message in timeout output. This helps when debugging defunct/zombie processes, e.g. "Execution timed out - Unable to TERM/KILL the process: Operation not permitted".

## [1.3.3] - 2018-04-18

### Fixed
- Posix spawn is now only used on x86_64 and i386 systems. (undo revert, a red herring)
- Now pinning FFI to 1.9.21, newer versions segfault on CentOS 6

## [1.3.2] - 2018-04-17

### Fixed
- Reverted posix spawn on only x86_64 and i386 systems, causing segfault on CentOS 6.

## [1.3.1] - 2018-04-12

### Fixed
- Posix spawn is now only used on x86_64 and i386 systems. This fixes Sensu on platforms where FFI is unable to compile.

## [1.3.0] - 2018-03-09

### Fixed
- Sensu TCP event handlers will no longer connect to a socket if the provided event data is nil or empty. (#1734)
- The RabbitMQ transport will now reconnect after failing to resolve DNS, instead of independently retrying broker hostname resolution. This fixes retry timer backoff and allows the transport to connect to another eligible broker after failing to resolve a hostname.

### Added
- Redis TLS connection support. Sensu Redis connections can now be configured to use TLS, this includes the Sensu server and Redis transport connections! The Sensu Redis configuration definition now includes the optional "tls" (or "ssl") attribute, a hash containing TLS options (`"private_key_file"`, `"cert_chain_file"`, and `"verify_peer"`).
- The Sensu client TCP/UDP socket can now be disabled via configuration.
- The Sensu client configuration definition now includes the socket "enabled" attribute, which defaults to `true`, and it can be set to `false` in order to disable the socket. (#1799)
- The Sensu Ruby gems are now cryptographically signed. To learn more about Ruby gem signing, [please refer to the RubyGems security guide](http://guides.rubygems.org/security/). (#1819)
- The Sensu API POST /clients endpoint no longer requires client subscriptions to be specified. (#1795)
- All Sensu event handler types now include event ID in log events.

## [1.2.1] - 2018-02-06
### Fixed
- Fixed a bug in which sensitive values deeply nested in arrays would not have been redacted.

## [1.2.0] - 2017-12-05
### Added
- Scheduled maintenance, Sensu now gives users the ability to silence a check and/or client subscriptions at a predetermined time (`begin` epoch timestamp), with an optional expiration (in seconds), enabling users to silence events in advance for scheduled maintenance windows.

- The Sensu API now logs the "X-Request-ID" header, making it much easier to trace a request/response. If the API client does not provide a request ID, the API generates one for the request (UUID).
- The Sensu API `/results/*` endpoints now include check history in the
result data.
- Check token substitution is now supported in check "source".

## [1.1.3] - 2017-11-24
### Fixed
- Fixed a bug in the Sensu client that broke check hooks named after numeric statuses (e.g. `"2"`) and `"non-zero"`, they were never executed unless the client had a local check definition. (#1773)

## [1.1.2] - 2017-10-27

### Fixed
- Fixed a bug in the Sensu client HTTP socket that caused the Sensu client to crash when the the local client definition did not specify `"http_socket"` settings and the `/info` or `/results` endpoints were accessed.

- Fixed a bug in the Sensu client HTTP socket that caused the Sensu client
to consider an HTTP content-type that included media-type information as
invalid, discarding possibly valid content.

## [1.1.1] - 2017-10-10
### Fixed
- Fixed a bug in check TTL monitoring that caused the Sensu server to crash. Check TTL member deletion, following the deletion of the associated check result, would produce an uncaught error.

## [1.1.0] - 2017-09-27
### Fixed
- Added initial timestamp to proxy client definitions. The Uchiwa and Sensu dashboards will no longer display "Invalid Date".
- Deleting check history when deleting an associated check result.

### Added
- Check hooks, commands run by the Sensu client in response to the result of the check command execution. The Sensu client will execute the appropriate configured hook command, depending on the check execution status (e.g. 1). Valid hook names include (in order of precedence): "1"-"255", "ok", "warning", "critical", "unknown", and "non-zero". The check hook command output, status, executed timestamp, and duration are captured and published in the check result. Check hook commands can optionally receive JSON serialized Sensu client and check definition data via STDIN.
- Check STDIN. A boolean check definition attribute, `"stdin"`, when set to `true` instructs the Sensu client to write JSON serialized Sensu client and check definition data to the check command process STDIN. This attribute cannot be used with existing Sensu check plugins, nor Nagios plugins etc, as the Sensu client will wait indefinitely for the check process to read and close STDIN.
- Splayed proxy check request publishing. Users can now splay proxy check requests (optional), evenly, over a window of time, determined by the check interval and a configurable splay coverage percentage. For example, if a check has an interval of 60s and a configured splay coverage of 90%, its proxy check requests would be splayed evenly over a time window of 60s * 90%, 54s, leaving 6s for the last proxy check execution before the the next round of proxy check requests for the same check. Proxy check request splayed publishing can be configured with two new check definition attributes, within the `proxy_requests` scope, `splay` (boolean) to enable it and `splay_coverage` (integer percentage, defaults to `90`).
- Configurable check output truncation (for storage in Redis). Check output truncation can be manually enabled/disabled with the check definition attribute "truncate_output", e.g.`"truncate_output": false`. The output truncation length can be configured with the check definition attribute "truncate_output_length", e.g. `"truncate_output_length": 1024`. Check output truncation is still enabled by default for metric checks, with `"type": "metric"`.
- Sensu client HTTP socket basic authentication can how be applied to all endpoints (not just `/settings`), via the client definition http_socket attribute "protect_all_endpoints", e.g. `"protect_all_endpoints": true`.

### Other

Improved check TTL monitoring performance.

The Sensu extension run log event log level is now set to debug (instead
of info) when the run output is empty and the status is 0.

## [1.0.3] - 2017-08-25
### Fixed
- Now using EventMachine version 1.2.5 in order to support larger EM timer intervals. EM timers are used by the Sensu check scheduler and many other Sensu components.

## [1.0.2] - 2017-07-27
### Fixed
- Addressed an issue with client keepalive transport acknowledgments. We discovered a situation where poor Redis performance could negatively impact client keepalive processing, potentially triggering a compounding failure that the Sensu server is unable to recover from. Moving acknowledgments to the next tick of the EventMachine reactor avoids the situation entirely.

## [1.0.1] - 2017-07-24
### Fixed
- Fixed Sensu configuration validation, it was not being applied.

## [1.0.0] - 2017-07-11
### Fixed
- Sensu handler severities filtering now accounts for flapping events.
- Fixed Sensu Redis connection on error reconnect, no longer reusing the existing EventMachine connection handler.

### Added
- Added Sensu API event endpoint alias "incidents", e.g. `/incidents`, `/incidents/:client/:check`.

### Changed
- Improved Sensu client keepalive configuration validation, now including
coverage for check low/high flap thresholds etc.
- Improved Sensu client socket check result validation, now including coverage for check low/high flap thresholds etc.
- The `sensu-install` tool now notifies users when it is unable to successfully install an extension, when the environment variable EMBEDDED_RUBY is set to `false`.

- Added the Sensu `RELEASE_INFO` constant, containing information about the Sensu release, used by the API `/info` endpoint and Server registration.



## [0.29.0] - 2017-03-29
### Fixed
- The built-in filter `occurrences` now supports `refresh` for flapping
events (action `flapping`).
- Force the configured Redis port to be an integer, as some users make the
mistake of using a string.

### Added
- Sensu server tasks, replacing the Sensu server leader functionality, distributing certain server responsibilities amongst the running Sensu servers. A server task can only run on one Sensu server at a time. Sensu servers partake in an election process to become responsible for one or more tasks. A task can failover to another Sensu server.
- Sensu API response object filtering for any GET request. Filtering is done with one or more dot notation query parameters, beginning with `filter.`, to specify object attributes to filter by, e.g. `/events?filter.client.environment=production&filter.check.contact=ops`.
- Added API endpoint GET `/settings` to provided the APIs running configuration. Sensitive setting values are redacted by default, unless the query parameter `redacted` is set to `false`, e.g. `/settings?redacted=false`.
- Added support for invalidating a Sensu client when deleting it via the Sensu API DELETE `/clients/:name` endpoint, disallowing further client keepalives and check results until the client is either successfully removed from the client registry or for a specified duration of time. To invalidate a Sensu client until it is deleted, the query parameter `invalidate` must be set to `true`, e.g. `/clients/app01.example.com?invalidate=true`. To invalidate the client for a certain amount of time (in seconds), the query parameter `invalidate_expire` must be set as well, e.g. `/clients/app01.example.com?invalidate=true&invalidate_expire=300`.
- Added a Sensu settings hexdigest, exposed via the Sensu API GET `/info` endpoint, providing a means to determine if a Sensu server's configuration differs from the rest.
- Added a proxy argument to `sensu-install`. To use a proxy for Sensu plugin and extension installation with `sensu-install`, use the `-x` or `--proxy` argument, e.g. `sensu-install -e statsd --proxy http://proxy.example.com:8080`.
- Added support for issuing proxy check requests via the Sensu API POST `/request` endpoint.
- The Sensu API now logs response times.
- The Sensu API now returns a 405 (Method Not Allowed) when an API endpoint does not support a HTTP request method, e.g. `PUT`, and sets the HTTP header "Allow" to indicate which HTTP request methods are supported by the requested endpoint.
- Added a built-in filter for check dependencies, `check_dependencies`, which implements the check dependency filtering logic in the Sensu Plugin library.
- Added default values for Sensu CLI options `config_file` (`"/etc/sensu/config.json"`) and `config_dirs` (`["/etc/sensu/conf.d"]`). These defaults are only applied when the associated file and/or directory exist.

### Changed
- Added a Rubocop configuration file and rake tasks for a slow introduction.

## [0.28.5] - 2017-03-23
### Fixed
- Fixed check `subdue` and filter `when` features when a time window spans over `00:00:00`, crossing the day boundary.

## [0.28.4] - 2017-03-10
### Fixed
- In the interest of addressing a regression causing duplicate check execution requests, code added in 0.28.0 to account for task scheduling drift has been removed.

## [0.28.3] - 2017-03-09
### Fixed
- The Sensu client now includes check source when tracking in progress check executions. These changes are necessary to allow the Sensu client to execute on several concurrent proxy check requests.

## [0.28.2] - 2017-03-03
### Fixed
- Clients created via /clients API endpoint now have a per-client subscription added automatically, ensuring they can be silenced.

## [0.28.1] - 2017-03-01
### Fixed
- Check requests with `proxy_requests` attributes are no longer overridden by local check definitions.
- Updated Oj (used by the sensu-json library) to the latest release (2.18.1) for Ruby 2.4 compatibility.

## [0.28.0] - 2017-02-23
### Fixed
- The Sensu interval timers, used for scheduling tasks, now account for drift. The check request and standalone execution scheduler timers are now more accurate.
- Fixed a bug in the Sensu `deep_merge()` method that was responsible for
mutating arrays of the original provided objects.

### Added
- Added proxy check requests to improve Sensu's ability to monitor external resources that have an associated Sensu proxy client. Publish a check request to the configured `subscribers` (e.g. `["round-robin:snmp_pollers"]`) for every Sensu client in the registry that matches the configured client attributes in `client_attributes` on the configured `interval` (e.g. `60`). Client tokens in the check definition (e.g. `"check-snmp-if.rb -h :::address::: -i eth0"`) are substituted prior to publishing the check request. The check request check `source` is set to the client `name`.
- Schedule check requests and standalone executions with the Cron syntax.
- Added the Sensu server registry, containing information about the running Sensu servers. Information about the Sensu servers is now accessible via the Sensu API `/info` endpoint.
- Added two optional attributes to Sensu API POST `/request`, `"reason"` and `"creator"`, for additional context. The check request reason and creator are added to the check request payload under `"api_requested"` and become part of the check result.
- Added event IDs to event handler log events for additional context, making it easier to trace an event through the Sensu pipeline.

## [0.27.1] - 2017-02-17
### Fixed
- Check subdue and filter when time windows now account for GMT offsets.
- Non UTF-8 characters in check tokens are now removed.
- Fixed filter name logging when an event is filtered.

### Changed
- Failed pipe handler executions are now logged with the error log level.
- Sensu server now adds a unique per-client subscription to client keepalives when missing. This is to enable built-in event silencing for older Sensu clients (< 0.26).

## [0.27.0] - 2017-01-26
### Breaking Changes

- The CONFIG_DIR environment variable has been renamed to CONFD_DIR. This environment varible is used to specify the directory path where	Sensu processes will load any JSON config files for deep merging. If you are using /etc/default/sensu to specify a custom value for CONFIG_DIR, please update it to the new CONFD_DIR variable name.

### Fixed
- Silenced resolution events with silencing `"expire_on_resolve": true` are now handled.

### Added
- Sensu client HTTP socket for check result input and informational queries. The client HTTP socket provides several endpoints, `/info`, `/results`, and `/settings`. Basic authentication is supported, which is required for certain endpoints, i.e. `/settings`. The client HTTP socket is configurable via the Sensu client definition, `"http_socket": {}`.
- Hostnames are now resolved prior to making connection attempts, this applies to the Sensu Transport (i.e. RabbitMQ) and Redis connections. This allows Sensu to handle resolution failures and enables failover via DNS and services like Amazon AWS ElastiCache.
- Added API endpoint `/silenced/ids/:id` for fetching a silence entry by id.
- Added check attribute `ttl_status`, allowing checks to set a different TTL event check status (default is `1` warning).
- Added client deregistration attribute `status`, allowing clients to set a different event check status for their deregistration events (default is `1` warning).
- Added Rubygems cleanup support to `sensu-install`, via the command line argument `-c/--clean` when installing one or more plugins and/or extensions. If a version is provided for the plugin(s) or extension(s), all other installed versions of them will be removed, e.g. `sensu-install -e snmp-trap:0.0.19 -c`. If a version is not provided, all installed versions except the latest will be removed.

### Changes
- Added the filter name to event filtered log events.
- Check TTL events now have the check interval overridden to the TTL monitoring interval, this change allows event occurrence filtering to work as expected.

## [0.26.5] - 2016-10-12
### Fixed
- Sensu client no longer fails to validate the client configuration when the automatic per-client subscription is the client's only subscription.

## [0.26.4] - 2016-10-05
### Fixed
- Sensu check extension executions are now properly tracked and the Sensu client now guards against multiple concurrent executions of the same extension.

## [0.26.3] - 2016-09-21
### Fixed
- Adjusted regular expression pattern to completely address scenarios where valid subscription names were not allowed via API `/silenced/subscriptions/:subscription` endpoint, e.g. `client:foo-bar-baz`.

## [0.26.2] - 2016-09-20
### Fixed
- Added logic to ensure proxy clients receive a per-client subscription upon creation so that they can be silenced via /silenced API.
- Updated API publish_check_result helper to address a condition where events could not be successfully deleted for clients configured with a signature.
- Fixed regexp in API which prevented retrieval of silence entries when requesting subscriptions containing a colon (e.g. `client:foo`, `roundrobin:bar`) on the `/silenced/subscriptions/:subscription` endpoint.
- Fixed a condition where processing check results with an invalid signature failed to complete. This often manifest as timeouts when waiting for sensu-server processes to terminate.

### Changes
- Default value for `client` settings has changed from `nil` to `{}`.

## [0.26.1] - 2016-09-07
### Fixes
- Fixed a Sensu server settings bug that cause sensu-server to required a client definition in order to start.

## [0.26.0] - 2016-09-06
### Breaking Changes
- Subdue now ONLY applies to check scheduling via check definitions, it has been removed from handlers (no more `"at": "handler"`). The subdue configuration syntax has changed, please refer to the [0.26 subdue documentation](https://sensuapp.org/docs/0.26/reference/checks.html#subdue-attributes).

### Fixed
- Increased the maximum number of EventMachine timers from 100k to 200k, to accommodate very large Sensu installations that execute over 100k checks.
- Only attempt to schedule standalone checks that have an interval.
- Standalone checks are no longer provided by the Sensu API /checks endpoint.
- Check TTL events are no longer created if the associated Sensu client has a current keepalive event.
- Fixed a Sensu API /results endpoint race condition that caused incomplete response content.

### Added
- Event silencing is now built into Sensu Core! The Sensu API now provides a set of /silenced endpoints, for silencing one or more subscriptions and/or checks. Silencing applies to all event handlers by default, the new handler definition attribute `handle_silenced` can be used to disable it for a handler. Metric check events (OK) bypass event silencing.

- Subdue now ONLY applies to check scheduling via check definitions, it has been removed from handlers (no more `"at": "handler"`). The Sensu client standalone check execution scheduler now supports subdue. The subdue configuration syntax has changed, please refer to the [0.26 subdue documentation](https://sensuapp.org/docs/0.26/reference/checks.html#subdue-attributes).

- Event filters now support time windows, via the filter definition attribute `"when": {}`. The configuration syntax is the same as check subdue.
- Sensu Extensions are now loaded from Rubygems! The Sensu installer, `sensu-install`, can now be used to install Sensu Extensions, e.g. `sensu-install -e system-profile`. Extensions gems must be enabled via Sensu configuration, please refer to the [0.26 extensions documentation](https://sensuapp.org/docs/0.26/reference/extensions.html#configuring-sensu-to-load-extensions).
- A check can now be a member of more than one aggregate, via the check
definition attribute `"aggregates": []`.
- Every Sensu client now creates/subscribes to its own unique client subscription named after it, e.g. `client:i-424242`. This unique client subscription allows Sensu checks to target a single client (host) and enables silencing events for a single client.

## [0.25.7] - 2016-08-09
### Fixed
- Fixed the Sensu API 204 status response string, changing "No Response" to the correct string "No Content".

## [0.25.6] - 2016-07-28
### Fixed
- Check results for unmatched tokens now include an executed timestamp.
- API aggregates max_age now guards against check results with a `nil` executed timestamp.

## [0.25.5] - 2016-07-12
### Fixed
- Reverted the Sensu API race condition fix, it was a red herring. Desired behaviour has been restored.
- Custom check definition attributes are now included in check request payloads, fixing check attribute token substitution for pubsub checks.
- Transport connectivity issues are now handled while querying the Transport for pipe stats for API `/info` and `/health`.

## [0.25.4] - 2016-06-20
### Fixed
- Fixed a race condition bug in the Sensu API where the `@redis` and
`@transport` objects were not initialized before serving API requests.

## 0.25.3 - 2016-06-17

### Fixed
- Fixed a bug in the Sensu API where it was unable to set the CORS HTTP headers when the API had not been configured (no `"api": {}` definition).

## [0.25.2] - 2016-06-16
### Fixed
- The Sensu API now responds to HEAD requests for GET routes.
- The Sensu API now responds to unsupported HTTP request methods with a 404 (Not Found), i.e. PUT.

## [0.25.1] - 2016-06-14
### Fixed
- The Sensu API now sets the HTTP response header "Connection" to "close". Uchiwa was experiencing intermittent EOF errors. [#1340](https://github.com/sensu/sensu/issues/1340)

## [0.25.0] - 2016-06-13

### Breaking Changes
- Sensu API legacy singular resources, e.g. `/check/:check_name`, have been removed. Singular resources were never documented and have not been used by most community tooling, e.g. Uchiwa, since the early Sensu releases.

### Fixes
- Fixed a critical bug in Sensu client `execute_check_command()` where a check result would contain a check command with client tokens substituted, potentially exposing sensitive/redacted client attribute values.

### Added
- The Sensu API has been rewritten to use EM HTTP Server, removing Rack and Thin as API runtime dependencies. The API no longer uses Rack async, making for cleaner HTTP request logic and much improved HTTP request and response logging.
- Sensu client auto de-registration on sensu-client process stop is now supported by the Sensu client itself, no longer depending on the package init script. The package init script de-registration functionality still remains, but is considered to be deprecated at this time.

## [0.24.1] - 2016-06-07
### Fixed
- Fixed a critical bug in Sensu server `resume()` which caused the server to crash when querying the state of the Sensu Transport connection before it had been initialized. [#1321](https://github.com/sensu/sensu/pull/1321)

### Changed
- Updated references to unmatched tokens, i.e. check result output message, to better represent the new scope of token substitution. [#1322](https://github.com/sensu/sensu/pull/1322)

## [0.24.0] - 2016-06-06
### Breaking Changes
- Sensu check ["Aggregates 2.0"](https://github.com/sensu/sensu/issues/1218) breaks the existing Sensu API aggregate endpoints.
- Sensu API GET /health endpoint, failed health checks now respond with a
`412` (preconditions failed) instead of a `503`.

### Added
- Persistent Sensu event IDs, event occurrences for a client/check pair will now have the same event ID until the event is resolved.

- Added a CLI option/argument to cause the Sensu service to validate its compiled configuration settings and exit with the appropriate exit code, e.g. `2` for invalid. The CLI option is `--validate_config`. This feature is now used when restarting a Sensu service to first validate the new configuration before stopping the running service.
- Improved tracking of in progress check result processing, no longer potentially losing check results when restarting the Sensu server service.
- Check results for proxy clients (a.k.a JIT clients) will now have a check "origin" set to the client name of the result producer.
- Configurable Sensu Spawn concurrent child process limit (checks, mutators, & pipe handlers). The default limit is still `12` and the EventMachine threadpool size is automatically adjusted to accommodate a larger limit.
- Sensu check ["Aggregates 2.0"](https://github.com/sensu/sensu/issues/1218).
- Sensu client token substitution is now supported in every check definition attribute value, no longer just the check command.

### Changed
- Event data check type now explicitly defaults to "standard".

### Fixed
- Sensu API GET /health endpoint, failed health check now responds with a
`412` (preconditions failed) instead of a `503`.
- Sensu API POST /clients endpoint can now create clients in the registry that are expected to produce keepalives, and validates clients with the Sensu Settings client definition validator.
- The Sensu API now listens immediately on service start, even before it has successfully connected to Redis and the Sensu Transport. It will now respond with a `500` response, with a descriptive error message, when it has not yet initialized its connections or it is reconnecting to either Redis or the Sensu Transport. The API /info and /health endpoints will still respond normally while reconnecting.

### Changed
- Updated Thin (used by Sensu API) to the latest version, 1.6.4.
- JrJackson is now used to parse JSON when Sensu is running on JRuby.

## [0.23.3] - 2016-05-26
### Fixes
- Fixed child process write/read deadlocks when writing to STDIN or reading from STDOUT/ERR, when the data size exceeds the pipe buffers.
- Fixed child process spawn timeout deadlock, now using stdlib Timeout.

## [0.23.2] - 2016-04-25
### Fixed
- Fixed client socket check result publishing when the client has a signature. The client signature is now added to the check result payload, making it valid.

### Added
- Added client socket check result check TTL validation.

## [0.23.1] - 2016-04-15
### Fixed
- The pure Ruby EventMachine reactor is used when running on Solaris.

## [0.23.0] - 2016-04-04
### Breaking Changes
- Dropped support for Rubies < 2.0.0, as they have long been EOL and have proven to be a hindrance and security risk.
- The Sensu Transport API changed. Transports are now a deferrable, they must call `succeed()` once they have fully initialized. Sensu now waits for its transport to fully initialize before taking other actions.

### Fixed
- Performance improvements. Dropped MultiJson in favour of Sensu JSON, a lighter weight JSON parser abstraction that supports platform specific parsers for Sensu Core and Enterprise. The Oj JSON parser is once again used for Sensu Core. Used https://github.com/JuanitoFatas/fast-ruby and benchmarks as a guide to further changes.
- Using EventMachine 1.2.0, which brings several changes and [improvements]( https://github.com/eventmachine/eventmachine/blob/master/CHANGELOG.md#1201-march-15-2016)

### Added
- Redis Sentinel support for HA Redis. Sensu services can now be configured to query one or more instances of Redis Sentinel for a Redis master. This feature eliminates the last need for HAProxy in highly available Sensu configurations. To configure Sensu services to use Redis Sentinel, hosts and ports of one or more Sentinel instances must be provided, e.g. `"sentinels": [{"host": "10.0.1.23", "port": 26479}]`.
- Added a CLI option/argument to cause the Sensu service to print (output to STDOUT) its compiled configuration settings and exit. The CLI option is `--print_config` or `-P`.
- Added token substitution to filter eval attributes, providing access to event data, e.g. `"occurrences": "eval: value == :::check.occurrences:::"`.
- The pure Ruby EventMachine reactor is used when running on AIX.
- The Sensu 0.23 packages use Ruby 2.3.

## [0.22.2] - 2016-03-16
### Fixed
- FFI library loading no longer causes a load error on AIX & Solaris.

### Removed
- Removed unused cruft from extension API `run()` and `safe_run()`. Optional `options={}` was never implemented in Sensu Core and event data `dup()` never provided the necessary protection that it claimed (only top level hash object).

## [0.22.1] - 2016-03-01
### Fixed
- Performance improvements. Using frozen constants for common values and comparisons. Reduced the use of block arguments for callbacks.
- Improved RabbitMQ transport channel error handling.
- Fixed client signatures inspection/comparison when upgrading from a
previous release.

## [0.22.0] - 2016-01-29

### Added
- Client registration events are optionally created and processed (handled, etc.) when a client is first added to the client registry. To enable this functionality, configure a "registration" handler definition on Sensu server(s), or define a client specific registration handler in the client definition, e.g. `{"client": "registration": {"handler": "debug"}}`.
- Client auto de-registration on sensu-client process stop is now supported by the Sensu package init script. Setting `CLIENT_DEREGISTER_ON_STOP=true` and `CLIENT_DEREGISTER_HANDLER=example` in `/etc/default/sensu` will cause the Sensu client to publish a check result to trigger the event handler named "example", before its process stops.
- Added support for Sensu client signatures, used to sign client keepalive and check result transport messages, for the purposes of source (publisher) verification. The client definition attribute "signature" is used to set the client signature, e.g. `"signature": "6zvyb8lm7fxcs7yw"`. A client signature can only be set once, the client must be deleted from the registry before its signature can be changed or removed. Client keepalives and check results that are not signed with the correct signature are logged (warn) and discarded. This feature is NOT a replacement for existing and proven security measures.
- The Sensu plugin installation tool, `sensu-install`, will no longer install a plugin if a or specified version has already been installed.
- The Sensu client socket now supports UTF-8 encoding.

## [0.21.0]- 2015-11-13

### Breaking Changes
- Using the Sensu embedded Ruby for Sensu checks, mutators, and handlers has become a common practice. The Sensu 0.21 packages changed the default
value of `EMBEDDED_RUBY` from `false` to `true`, allowing Sensu plugins to use the embedded Ruby by default. This change makes it easier to get started with Sensu.

### Fixed
- Improved the Sensu test suite to reduce the number of timeout triggered failures. These changes make Sensu development much more pleasant.
- Fixed a few inline documentation typos, e.g. sbuded -> subdued.
- Moved the Sensu bins (e.g. `sensu-client`) from `bin` to `exe` to avoid the conflict with Ruby bundler bin stubs.
- Fixed Sensu API and client socket input validation, no longer accepting
multi-line values.
- Fixed check request publishing for checks that make use of check extensions, e.g. `"extension": "check_http_endpoints`.
- Fixed the handler `"filters"` bug that caused Sensu to mutate handler definitions, removing filters for successive executions.
- Fixed Sensu API POST /request endpoint check request publishing to round-robin client subscriptions.
- Fixed the Windows job handle leak when spawning processes for checks.
- Updated the Redis client library (em-redis-unified) to remove duplicate
Ruby hash key warnings.

### Added
- Added a Sensu plugin installation tool, `sensu-install`, making it easier to install Sensu community plugins. The `sensu-install` tool will use the appropriate Ruby when installing plugins. The tool aims to produce verbose and useful output to help when debugging plugin installation issues.
- Added the Sensu API DELETE /results/:client/:check endpoint, supporting check result deletion via the Sensu API. This feature allows users to clean up "stale" check result data for checks that have been removed.
- Added the Sensu API POST /results endpoint, supporting check result input via the Sensu API. The JIT client feature added in 0.20 enabled this functionality. Services that do not have access to a local Sensu client socket can make use of this feature.

## [0.20.6] - 2015-09-22
### Fixed
- Removed the use of `EM::Iterator` from event filtering, replacing it with `Proc` and `EM::next_tick`. `EM::Iterator` creates anonymous classes that cannot be garbage collected on JRuby.
- The Sensu API will remove a client immediately if there are no current events for it. The API will continue to monitor the current event count for the client to be deleted, deleting the client when there are no longer current events or after a timeout of 5 seconds.
- The Sensu API will no longer crash while fetching check result data for a
client that is being deleted.

### Removed
- Removed sensu-em as a dependency, now using upstream EventMachine 1.0.8.

## [0.20.5] - 2015-09-09
### Fixed
- Updated sensu-spawn to 1.4.0, adding a mutex to ChildProcess Unix POSIX spawn, allowing safe execution on Ruby runtimes with real threads (JRuby).
- Fixed metric check output truncation when output is empty.

## [0.20.4] - 2015-08-28
### Fixed
- Improved check output truncation. Metric check output is truncated to a single line and 256 characters. Standard check output is not modified.
- Fixed API /results endpoint, now including all results in a single response (unless pagination is used).
- Locked amq-protocol to 1.9.2, as 2.x.x does not work on older Rubies.
- Fixed pipe handler output logging on JRuby.

## [0.20.3] - 2015-08-11
### Fixed
- Improved Sensu server leader election and resignation. Changes include the use of a unique leader ID to help guard against cases where there could be multiple leaders.
- Fixed bridge extensions; they now receive all event data, including events that normally do not result in an action (e.g. OK check results).

## [0.20.2] - 2015-08-06
### Fixed
- The Sensu API `/clients` route/endpoint is now capable of handling missing client data for a client in the registry.
- Sensu configuration file loading will now properly follow a link once.

## [0.20.1] - 2015-07-27
### Fixed
- Resolving an event, that includes a check TTL, with the Sensu API will remove the check from TTL monitoring, until another check result with a TTL is received.
- Added a timestamp to Sensu event data, recording the time of event
creation.
- Fixed RabbitMQ transport connection AMQP heartbeat monitoring, the AMQP
library was sending heartbeat frames on closed connections.
- The RabbitMQ transport now resets (close connection, etc.) when making
periodic reconnect attempts. The periodic reconnect timer delay will now
be incremented by 2 on every attempt, to a maximum of 20 seconds.

## [0.20.0] - 2015-07-09
### Fixed
- The Sensu event action is now correctly set to "create" for metric check events.
- Updated MultiJson and Childprocess to the latest versions, which include improvements and bug fixes.
- Sensu now sets the `SENSU_LOADED_TEMPFILE` environment variable to a temporary file path, a file containing the colon delimited list of loaded configuration files for the Sensu service (e.g.`/tmp/sensu_client_loaded_files`). This new temporary file and environment variable (`SENSU_LOADED_TEMPFILE`) replaced `SENSU_CONFIG_FILES`, which has been removed, due to the exec ARG_MAX (E2BIG) error when spawning processes after loading many configuration files (e.g. > 2000).

### Added
- Sensu services now optionally load connection and client configuration from environment variables. This feature makes it easier to operate Sensu in containerized environments, e.g. Docker. Sensu services read configuration from the following variables: `SENSU_TRANSPORT_NAME`, `RABBITMQ_URL`, `REDIS_URL`, `SENSU_CLIENT_NAME`, `SENSU_CLIENT_ADDRESS`, `SENSU_CLIENT_SUBSCRIPTIONS`, and `SENSU_API_PORT`

## [0.19.2] - 2015-06-08
### Fixed
- Updated sensu-em to fix UDP handlers when running on JRuby, open files
were not being closed/released properly.

## [0.19.1] - 2015-06-04
### Fixed
- Now using an EventMachine timer for the TCP handler connection timeout, as `pending_connect_timeout()` and `comm_inactivity_timeout()` are not currently supported on all platforms.
- Updated Thin and UUID tools to the latest versions, which include
improvements and bug fixes.

## [0.19.0] - 2015-06-01
### Fixed
- POSIX spawn libraries are now loaded upfront/immediately, not at child process creation. This removes the possibility of load race conditions when real threads are used.
- Many Ruby EventMachine fixes and improvements, including FD_CLOEXEC for the Sensu client UDP socket.
- Fixed event resolution for flapping events.
- Check source is now published in check requests if configured. Including
- the check source in check requests fixes JIT clients for standard (pubsub) check executions and adds context to client check execution log events.
- JIT clients now have a Sensu version, set to the Sensu server version.

### Added
- Redis Sensu transport, a built-in alternative to the default RabbitMQ transport. The Redis transport is currently considered experimental. Configuring the transport name to be `redis` will enable the Redis transport instead of RabbitMQ, e.g. `{"transport": {"name": "redis"}}`.
- Round-robin client subscriptions, allowing check requests to be sent to a single client in a subscription in a round-robin fashion. To create a round-robin subscription, start its name with `roundrobin:` to specify the type, e.g. "roundrobin:elasticsearch". Any check that targets the `"roundrobin:elasticsearch"` subscription will have its check requests sent to clients in a round-robin fashion.
- Stale check result detection, using a defined check `ttl` and stored check results. Sensu is now able to monitor check results, ensuring that checks with a defined TTL (time to live) continue to be executed by clients. For example, a standalone check could have an interval of 30 seconds and a ttl of 50 seconds, Sensu would expect a result at least once every 50 seconds.
- Check results API routes/endpoints: `/results`, `/results/:client`, and `/results/:client/:check`. These new check result API routes/endpoints enable new tooling, such as green light dashboards.

## [0.18.1] - 2015-05-11
### Fixed
- Check source is now validated for check results written to the Sensu
client socket(s), using the same regular expression as the configuration
attribute validator.
- The latest versions of Ruby Sinatra and Async Sinatra are now used,
which include many improvements and bug fixes.
- Added a caret to the beginning of API routes/endpoints that use regular
expressions, fixing a bug that caused the wrong route/endpoint to be
called, e.g. `/clients/client`.
- Check results written to the Sensu client socket(s) now have a default
executed timestamp, equal to the current Unix/epoch time.

## [0.18.0] - 2015-05-05
### Fixed
- The Sensu client sockets (TCP/UDP) are now stopped/closed before the
process is stopped.

### Added
- Dynamic (or JIT) client creation (in the registry) for check results for a nonexistent client or a check source. Sensu clients can now monitor an external resource on its behalf, using a check `source` to create a JIT client for the resource, used to store the execution history and provide context within event data. JIT client data in the registry can be managed/updated via the Sensu API, POST `/clients`.
- Storing the latest check result for every client/check pair. This data is currently exposed via the API at `/clients/:client/history` and will be used by several upcoming features.
- The Sensu API now listens on TCP port `4567` by default.
- Sensu server leader election lock timestamps now include milliseconds to reduce the chance of a conflict when attempting to elect a new leader.
- Sensu transport "reconnect_on_error" now defaults to `true`. For the
RabbitMQ transport, this means AMQP channel errors will result in a
reconnect. The Sensu transport will always reconnect when there is a loss
of connectivity.

### Changed
- Sensu server "master" election is now "leader" election.
- Configuration file encoding is now forced to 8-bit ASCII and UTF-8 BOMs
are removed if present.

## [0.17.2] - 2015-04-08
### Fixed
- Fixed a bug where the Sensu server was unable to stop due to the handling event count not being decremented when events were filtered.

## [0.17.1] - 2015-03-30
### Added
- Check requests can now include a check "extension" to run, instead of a
command.

### Changed
- Always merge check requests with local check definitions if they exist.

## [0.17.0] - 2015-03-17
### Fixed
- Fixed TLS/SSL on Windows.
- Fixed event filtering with event action, eg. `"action": "create"`.
- Bumped MultiJSON to 1.11.0, to make adapters read IO objects prior to
load.

### Added
- Improved Sensu client keepalive event check output.
- Hashed initial check request/execution scheduling splay, consistent over process restarts/reloads.
- Handler output with multiple lines is now logged as a single log event.
- Support for Sensu filter extensions.
- Check definitions can now specify a Sensu check extension to run,
"extension", instead of a command.
- Sensu transport "reconnect_on_error" configuration option, to enable
transport reconnect in the event of an unexpected error. This is set to
false by default, as some errors are unrecoverable. The Sensu transport
will always reconnect when there is a loss of connectivity.
- Sensu Redis "reconnect_on_error" configuration option, to enable Redis
reconnect in the event of an unexpected error. This is set to false by
default, as some errors are unrecoverable. The Redis client will always
reconnect when there is a loss of connectivity.

### Changed
- Restructured and documented Sensu core with YARD.

## [0.16.0] - 2014-10-31
### Fixed
- Fixed RabbitMQ transport configuration backwards compatibility.

## [0.15.0] - 2014-10-31
### Added
- RabbitMQ transport now supports multiple broker connection options,
enabling connection fail-over to brokers in a cluster without
using a load balancer.

## [0.14.0] - 2014-09-29
### Fixed
- Child process manager now supports check output larger than the max OS
buffer size. The parent process was waiting on the child to exit before closing its write end of the pipe.
- Client & server are now guarding against invalid JSON transport payloads.

### Added
- Client socket now supports sending a result via a TCP stream. This feature allows check results to have larger output (metrics, backtraces, etc).
- API now supports CORS (configurable).
- Check "source" attribute validation; it must be a string, event data
consumers no longer have to validate it.

## [0.13.1] - 2014-07-28

### Fixed
Fixed event occurrence count.

## [0.13.0] - 2014-06-12
### Breaking Changes
- API GET /events now provides all event data, the same data passed to event handlers.
- AMQP handler type ("amqp") has been replaced by "transport".
- Standalone check results are no longer merged with check definitions residing on the server(s).
- Removed the generic extension type.
- Extension stop() no longer takes a callback, and is called when the
eventmachine reactor is stopped.

### Fixed
- Clients now only load instances of check extensions, and servers load
everything but check extensions.
- Fixed standalone check scheduling, no longer mutating definitions.
- Fixed command token substitution, allowing for the use of colons and
working value defaults.
- Log events are flushed when the eventmachine reactor stops.
- Dropped the Oj JSON parser, heap allocation issues and memory leaks.
- Client RabbitMQ queues are no longer server named (bugs), they are now
composed of the client name, Sensu version, and the timestamp at creation.

### Added
- Abstracted the transport layer, opening Sensu up to alternative messaging services.
- Event bridge extension type, allowing all events to be relayed to other
services.
- Client keepalives now contain the Sensu version.
- Support for nested handler sets (not deep).
- Setting validation reports all invalid definitions before Sensu exits.

### Changed
- Server master election lock updates and queries are more frequent.

## [0.12.6] - 2014-02-19
### Breaking Changes

- The "profiler" extension type `Sensu::Extension::Profiler` is now "generic" `Sensu::Extension::Generic`.

## [0.12.5] - 2014-01-20
### Fixed
- Fixed handler severity filtering, check history is an array of strings.

## [0.12.4] - 2014-01-17
### Fixed
- Fixed filter "eval:" on Ruby 2.1.0, and logging errors.
- Fixed handler severity filtering when event action is "resolve". Events
with an action of "resolve" will be negated if the severity conditions have not been met since the last OK status.

## [0.12.3] - 2013-12-19
### Breaking Changes
- The pipe handler and mutator concurrency limit is now imposed by
`EM::Worker`. A maximum of 12 processes may be spawned at a time.

## [0.12.2] - 2013-11-22
### Fixed
- RabbitMQ connection closed errors are now rescued when attempting to publish to an exchange, while Sensu is reconnecting.

### Changed
- API routes now have an optional trailing slash.
- RabbitMQ initial connection timeout increased from 10 to 20 seconds.

## [0.12.1] - 2013-11-02
### Fixed
- Fixed a config loading bug where Sensu was not ignoring files without a
valid JSON object.
- Fixed `handling event` log line data for extensions.

### Added
- API GET `/stashes` now returns stash expiration information, time
remaining in seconds. eg. [{"path": "foo", "content":{"bar": "baz"},
"expire": 3598}].

## [0.12.0] - 2013-10-28
### Breaking Changes
- Deprecated API endpoints, `/check/request` and `/event/resolve`, have been removed. Please use `/request` and `/resolve`.

### Fixed
- Added additional AMQP library version constraints.
- Improved API POST data validation.

### Added
- API stashes can now expire, automatically removing themselves after `N`
seconds, eg. '{"path": "foo", "content":{"bar": "baz"}, "expire": 600}'.

## [0.11.3] - 2013-10-23
### Fixed
- Fixed redacting sensitive information in log lines during configuration
loading.
- Fixed AMQP library dependency version resolution.
- Changed to an older version of the JSON parser, until the source of a
memory leak is identified.

## [0.11.2] - 2013-10-23
### Added

- Sensu profiler extension support.
- Added logger() to the extension API, providing access to the Sensu logger.

## [0.11.1] - 2013-10-16
### Fixed
- Updated "em-redis-unified" dependency version lock, fixing Redis
reconnect when using authentication and/or select database.

## [0.11.0] - 2013-10-02
### Breaking Changes
- Extensions compatible with previous versions of Sensu will NO LONGER FUNCTION until they are updated for Sensu 0.11.x! Extensions are an experimental feature and not widely used.
- Sensu settings are now part of the extension API & are no longer passed
as an argument to run.

- TCP handlers no longer have a socket timeout, instead they have a
handler timeout for consistency.

### Fixed
- Sensu passes a dup of event data to mutator & handler extensions to
prevent mutation.
- Extension runs are wrapped in a begin/rescue block, a safety net.
- UDP handler now binds to "0.0.0.0".
- Faster JSON parser.
- AMQP connection heartbeats will no longer attempt to use a closed channel.
- Missing AMQP connection heartbeats will result in a reconnect.
- The keepalive & result queues will now auto-delete when there are no active consumers. This change stops the creation of a keepalive/result backlog, stale data that may overwhelm the recovering consumers.
- Improved Sensu client socket check validation.
- AMQP connection will time out if the vhost is missing, there is a lack
of permissions, or authentication fails.

### Added
- You can specify the Sensu log severity level using the -L (--log_level)
CLI argument, providing a valid level (eg. warn).
- You can specify custom sensitive Sensu client key/values to be redacted from log events and keepalives, eg. `"client": { "redact": [ "secret_access_key" ] }`.
- You can configure the Sensu client socket (UDP & TCP), bind & port, eg.
`"client": { "socket": { "bind": "0.0.0.0", "port": 4040 } }`.
- Handlers & mutators can now have a timeout, in seconds.
- You can configure the RabbitMQ channel prefetch value (advanced), eg. "rabbitmq": { "prefetch": 100 }.

## [0.10.2] - 2013-07-18
### Fixed
- Fixed redacting passwords in client data, correct value is now provided
to check command token substitution.

## [0.10.1] - 2013-07-17
### Fixed
- Catches nil exit statuses, returned from check execution.
- Empty command token substitution defaults now work. eg. "-f :::bar|:::"
- Specs updated to run on OS X, bash compatibility.

### Added
- You can specify multiple Sensu service configuration directories,
using the -d (--config_dir) CLI argument, providing a comma delimited
list.
- A post initialize hook ("post_init()") was added to the extension API,
enabling setup (connections, etc.) within the event loop.

## [0.10.0] - 2013-06-27
### Breaking Changes
- Client & check names must not contain spaces or special characters.
The valid characters are: `a-z, A-Z, 0-9, "_", ".", and "-"`.
- "command_executed" was removed from check results, as it may contain sensitive information, such as credentials.

### Fixed
- Fixed nil check status when check does not exit.
- Fixed the built-in debug handler output encoding (JSON).

### Added
- Passwords in client data (keepalives) and log events are replaced with "REDACTED", reducing the possibility of exposure. The following attributes will have their values replaced: `"password", "passwd", and "pass"`.

## [0.9.13] - 2013-05-20
### Fixed
- Validating check results, as bugs in older Sensu clients may produce invalid or malformed results.
- Improved stale client monitoring, to better handle client deletions.
- Improved check validation, names must not contain spaces or special
characters, & an "interval" is not required when "publish" is false.

### Added
- The Sensu API now provides /health, an endpoint for connection & queue monitoring. Monitor Sensu health with services like Pingdom.
- Sensu clients can configure their own keepalive handler(s) & thresholds.
- Command substitution tokens can have default values (eg. `:::foo.bar|default:::`).
- Check result (& event) data now includes "command_executed", the command after token substitution.

## [0.9.12] - 2013-04-03
### Breaking Changes
- The Sensu API stashes route changed, GET /stashes now returns an array of stash objects, with support for pagination. The API no longer uses POST for multi-get.
- Sensu services no longer have config file or directory defaults. Configuration paths a left to packaging.

### Fixed
- All Sensu API 201 & 202 status responses now return a body.
- The Sensu server now "pauses" when reconnecting to RabbitMQ. Pausing the Sensu server when reconnecting to RabbitMQ fixes an issue when it is also reconnecting to Redis.
- Keepalive checks now produce results with a zero exit status, fixing keepalive check history.
- Replaced the JSON parser with a faster implementation.
- Replaced the Sensu logger with a more lightweight & EventMachine friendly implementation. No more TTY detection with colours.
- Improved config validation.

### Added
- The Sensu API now provides client history, providing a list of executed checks, their status histories, and last execution timestamps. The client history endpoint is /clients/\<client-name\>/history, which returns a JSON body.
- The Sensu API can now bind to a specific address. To bind to an address, use the API configuration key "bind", with a string value (eg. "127.0.0.1").
- A stop hook was added to the Sensu extension API, enabling gracefull
stop for extensions. The stop hook is called before the event loop comes to a halt.
- The Sensu client now supports check extensions, checks the run within the Sensu Ruby VM, for aggresive service monitoring & metric collection.
- Sensu runs on Ruby 2.0.0p0.

## [0.9.11] - 2013-02-22
### Breaking Changes
- Removed /info "health" in favor of RabbitMQ & Redis "connected".

### Fixed
- No longer using the default AMQP exchange or publishing directly to queues.
- Removed API health filter, as the Redis connection now recovers.
- Fixed config & extension directory loading on Windows.
- Client socket handles non-ascii input.

### Added
- API aggregate age filter parameter.

## [0.9.10] - 2013-01-30
### Breaking Changes
- Extensions have access to settings.

### Fixed
- Client queue names are now determined by the broker (RabbitMQ).
- Improved zombie reaping.

### Added
- Handlers can be subdued like checks, suppression windows.

## [0.9.9] - 2013-01-14
### Fixed
- Server is now using basic AMQP QoS (prefetch), just enough back pressure.
- Improved check execution scheduling.
- Fixed server execute command method error handling.
- Events with a resolve action bypass handler severity filtering.
- Check flap detection configuration validation.

### Added
- RabbitMQ keepalives & results queue message and consumer counts available via the API (/info).
- Aggregate results available via the API when using a parameter `(?results=true)`.
- Event filters; filtering events for handlers, using event attribute matching.
- TCP handler socket timeout, which defaults to 10 seconds.
- Check execution timeout.
- Server extensions (mutators & handlers).

## [0.9.8] - 2012-11-15
### Fixed
- Fixed flap detection.
- Gracefully handle possible failed RabbitMQ authentication.
- Catch and log AMQP channel errors, which cause the channel to close.
- Fixed API event resolution handling, for events created by standalone checks.
- Minor performance improvements.

### Added
- Aggregates, pooling and summarizing check results, very handy for monitoring a horizontally scaled or distributed system.
- Event handler severities, only handle events that have specific
severities.

## [0.9.7] - 2012-09-20
### Breaking Changes
- AMQP handlers can no longer use `"send_only_check_output": true`, but instead have access to the built-in mutators `"mutator": "only_check_output"` and `"mutator": "only_check_output_split"`.
- Ruby 1.8.7-p249 is no longer supported, as the AMQP library no longer does. Please use the Sensu APT/YUM packages which contain an embedded Ruby.
- Client expects check requests to contain a command, be sure to upgrade servers prior to upgrading clients.
- Check subdue options have been modified, "start" is now "begin".

### Fixed
- Improved RabbitMQ and Redis connection recovery.
- Fixed API POST input validation.
- Redis client connection heartbeat.
- Improved graceful process termination.
- Improved client socket ping/pong.
- Strict dependency version locking.
- Adjusted logging level for metric events.

### Added
- Event data mutators, manipulate event data and its format prior to
sending to a handler.
- TCP and UDP handler types, for writing event data to sockets.
- API resources now support singular & plural, Rails friendly.
- Client safe mode, require local check definition in order to execute a check, disable for simpler deployment (default).
