## 1.0.0 - TBD

### Features

Added Sensu API event endpoint alias "incidents", e.g. `/incidents`,
`/incidents/:client/:check`.

### Other

Improved Sensu client keepalive configuration validation, now including
coverage for check low/high flap thresholds etc.

Improved Sensu client socket check result validation, now including
coverage for check low/high flap thresholds etc.

The `sensu-install` tool now notifies users when it is unable to
successfully install an extension, when the environment variable
EMBEDDED_RUBY is set to `false`.

Added the Sensu `RELEASE_INFO` constant, containing information about the
Sensu release, used by the API `/info` endpoint and Server registration.

### Fixes

Sensu handler severities filtering now accounts for flapping events.

Fixed Sensu Redis connection on error reconnect, no longer reusing the
existing EventMachine connection handler.

## 0.29.0 - 2017-03-29

### Features

Sensu server tasks, replacing the Sensu server leader functionality,
distributing certain server responsibilities amongst the running Sensu
servers. A server task can only run on one Sensu server at a time. Sensu
servers partake in an election process to become responsible for one or
more tasks. A task can failover to another Sensu server.

Sensu API response object filtering for any GET request. Filtering is done
with one or more dot notation query parameters, beginning with `filter.`,
to specify object attributes to filter by, e.g.
`/events?filter.client.environment=production&filter.check.contact=ops`.

Added API endpoint GET `/settings` to provided the APIs running
configuration. Sensitive setting values are redacted by default, unless
the query parameter `redacted` is set to `false`, e.g.
`/settings?redacted=false`.

Added support for invalidating a Sensu client when deleting it via the
Sensu API DELETE `/clients/:name` endpoint, disallowing further client
keepalives and check results until the client is either successfully
removed from the client registry or for a specified duration of time. To
invalidate a Sensu client until it is deleted, the query parameter
`invalidate` must be set to `true`, e.g.
`/clients/app01.example.com?invalidate=true`. To invalidate the client for
a certain amount of time (in seconds), the query parameter
`invalidate_expire` must be set as well, e.g.
`/clients/app01.example.com?invalidate=true&invalidate_expire=300`.

Added a Sensu settings hexdigest, exposed via the Sensu API GET `/info`
endpoint, providing a means to determine if a Sensu server's configuration
differs from the rest.

Added a proxy argument to `sensu-install`. To use a proxy for Sensu plugin
and extension installation with `sensu-install`, use the `-x` or
`--proxy` argument, e.g. `sensu-install -e statsd --proxy
http://proxy.example.com:8080`.

Added support for issuing proxy check requests via the Sensu API POST
`/request` endpoint.

The Sensu API now logs response times.

The Sensu API now returns a 405 (Method Not Allowed) when an API endpoint
does not support a HTTP request method, e.g. `PUT`, and sets the HTTP
header "Allow" to indicate which HTTP request methods are supported by the
requested endpoint.

Added a built-in filter for check dependencies, `check_dependencies`,
which implements the check dependency filtering logic in the Sensu Plugin
library.

Added default values for Sensu CLI options `config_file`
(`"/etc/sensu/config.json"`) and `config_dirs` (`["/etc/sensu/conf.d"]`).
These defaults are only applied when the associated file and/or directory
exist.

### Other

Added a Rubocop configuration file and rake tasks for a slow introduction.

### Fixes

The built-in filter `occurrences` now supports `refresh` for flapping
events (action `flapping`).

Force the configured Redis port to be an integer, as some users make the
mistake of using a string.

## 0.28.5 - 2017-03-23

### Fixes

Fixed check `subdue` and filter `when` features when a time window spans
over `00:00:00`, crossing the day boundary.

## 0.28.4 - 2017-03-10

### Fixes

In the interest of addressing a regression causing duplicate check
execution requests, code added in 0.28.0 to account for task scheduling
drift has been removed.

## 0.28.3 - 2017-03-09

### Fixes

The Sensu client now includes check source when tracking in progress check
executions. These changes are necessary to allow the Sensu client to
execute on several concurrent proxy check requests.

## 0.28.2 - 2017-03-03

### Fixes

Clients created via /clients API endpoint now have a per-client
subscription added automatically, ensuring they can be silenced.

## 0.28.1 - 2017-03-01

### Fixes

Check requests with `proxy_requests` attributes are no longer
overridden by local check definitions.

Updated Oj (used by the sensu-json library) to the latest release (2.18.1)
for Ruby 2.4 compatibility.

## 0.28.0 - 2017-02-23

### Features

Added proxy check requests to improve Sensu's ability to monitor external
resources that have an associated Sensu proxy client. Publish a check
request to the configured `subscribers` (e.g.
`["round-robin:snmp_pollers"]`) for every Sensu client in the registry
that matches the configured client attributes in `client_attributes` on
the configured `interval` (e.g. `60`). Client tokens in the check
definition (e.g. `"check-snmp-if.rb -h :::address::: -i eth0"`) are
substituted prior to publishing the check request. The check request check
`source` is set to the client `name`.

Schedule check requests and standalone executions with the Cron syntax.

Added the Sensu server registry, containing information about the running
Sensu servers. Information about the Sensu servers is now accessible via
the Sensu API `/info` endpoint.

Added two optional attributes to Sensu API POST `/request`, `"reason"` and
`"creator"`, for additional context. The check request reason and creator
are added to the check request payload under `"api_requested"` and become
part of the check result.

Added event IDs to event handler log events for additional context, making
it easier to trace an event through the Sensu pipeline.

### Fixes

The Sensu interval timers, used for scheduling tasks, now account for
drift. The check request and standalone execution scheduler timers are now
more accurate.

Fixed a bug in the Sensu `deep_merge()` method that was responsible for
mutating arrays of the original provided objects.

## 0.27.1 - 2017-02-17

### Other

Failed pipe handler executions are now logged with the error log level.

Sensu server now adds a unique per-client subscription to client
keepalives when missing. This is to enable built-in event silencing for
older Sensu clients (< 0.26).

### Fixes

Check subdue and filter when time windows now account for GMT offsets.

Non UTF-8 characters in check tokens are now removed.

Fixed filter name logging when an event is filtered.

## 0.27.0 - 2017-01-26

### Features

Sensu client HTTP socket for check result input and informational queries.
The client HTTP socket provides several endpoints, `/info`, `/results`,
and `/settings`. Basic authentication is supported, which is required for
certain endpoints, i.e. `/settings`. The client HTTP socket is
configurable via the Sensu client definition, `"http_socket": {}`.

Hostnames are now resolved prior to making connection attempts, this
applies to the Sensu Transport (i.e. RabbitMQ) and Redis connections. This
allows Sensu to handle resolution failures and enables failover via DNS
and services like Amazon AWS ElastiCache.

Added API endpoint `/silenced/ids/:id` for fetching a silence entry by id.

Added check attribute `ttl_status`, allowing checks to set a different TTL
event check status (default is `1` warning).

Added client deregistration attribute `status`, allowing clients to set a
different event check status for their deregistration events (default is
`1` warning).

Added Rubygems cleanup support to `sensu-install`, via the command line
argument `-c/--clean` when installing one or more plugins and/or
extensions. If a version is provided for the plugin(s) or extension(s),
all other installed versions of them will be removed, e.g. `sensu-install
-e snmp-trap:0.0.19 -c`. If a version is not provided, all installed
versions except the latest will be removed.

### Other

Added the filter name to event filtered log events.

Check TTL events now have the check interval overridden to the TTL
monitoring interval, this change allows event occurrence filtering to
work as expected.

### Fixes

Silenced resolution events with silencing `"expire_on_resolve": true` are
now handled.

## 0.26.5 - 2016-10-12

### Fixes

Sensu client no longer fails to validate the client configuration when the
automatic per-client subscription is the client's only
subscription.

## 0.26.4 - 2016-10-05

### Fixes

Sensu check extension executions are now properly tracked and the Sensu
client now guards against multiple concurrent executions of the same
extension.

## 0.26.3 - 2016-09-21

### Fixes

Adjusted regular expression pattern to completely address scenarios where
valid subscription names were not allowed via API
`/silenced/subscriptions/:subscription` endpoint, e.g.
`client:foo-bar-baz`.

## 0.26.2 - 2016-09-20

### Fixes

Added logic to ensure proxy clients receive a per-client subscription upon
creation so that they can be silenced via /silenced API.

Updated API publish_check_result helper to address a condition where
events could not be successfully deleted for clients configured with a
signature.

Fixed regexp in API which prevented retrieval of silence entries when
requesting subscriptions containing a colon (e.g. `client:foo`,
`roundrobin:bar`) on the `/silenced/subscriptions/:subscription` endpoint.

Fixed a condition where processing check results with an invalid signature
failed to complete. This often manifest as timeouts when waiting for
sensu-server processes to terminate.

### Changes

Default value for `client` settings has changed from `nil` to `{}`.

## 0.26.1 - 2016-09-07

### Fixes

Fixed a Sensu server settings bug that cause sensu-server to required a
client definition in order to start.

## 0.26.0 - 2016-09-06

### Non-backwards compatible changes

Subdue now ONLY applies to check scheduling via check definitions, it has
been removed from handlers (no more `"at": "handler"`). The subdue
configuration syntax has changed, please refer to the [0.26 subdue
documentation](https://sensuapp.org/docs/0.26/reference/checks.html#subdue-attributes).

### Fixes

Increased the maximum number of EventMachine timers from 100k to 200k, to
accommodate very large Sensu installations that execute over 100k checks.

Only attempt to schedule standalone checks that have an interval.

Standalone checks are no longer provided by the Sensu API /checks endpoint.

Check TTL events are no longer created if the associated Sensu client has
a current keepalive event.

Fixed a Sensu API /results endpoint race condition that caused incomplete
response content.

### Features

Event silencing is now built into Sensu Core! The Sensu API now provides a
set of /silenced endpoints, for silencing one or more subscriptions
and/or checks. Silencing applies to all event handlers by default, the new
handler definition attribute `handle_silenced` can be used to disable it
for a handler. Metric check events (OK) bypass event silencing.

Subdue now ONLY applies to check scheduling via check definitions, it has
been removed from handlers (no more `"at": "handler"`). The Sensu client
standalone check execution scheduler now supports subdue. The subdue
configuration syntax has changed, please refer to the [0.26 subdue
documentation](https://sensuapp.org/docs/0.26/reference/checks.html#subdue-attributes).

Event filters now support time windows, via the filter definition
attribute `"when": {}`. The configuration syntax is the same as check
subdue.

Sensu Extensions are now loaded from Rubygems! The Sensu installer,
`sensu-install`, can now be used to install Sensu Extensions, e.g.
`sensu-install -e system-profile`. Extensions gems must be enabled via
Sensu configuration, please refer to the [0.26 extensions
documentation](https://sensuapp.org/docs/0.26/reference/extensions.html#configuring-sensu-to-load-extensions).

A check can now be a member of more than one aggregate, via the check
definition attribute `"aggregates": []`.

Every Sensu client now creates/subscribes to its own unique client
subscription named after it, e.g. `client:i-424242`. This unique client
subscription allows Sensu checks to target a single client (host) and
enables silencing events for a single client.

## 0.25.7 - 2016-08-09

### Fixes

Fixed the Sensu API 204 status response string, changing "No Response" to
the correct string "No Content".

## 0.25.6 - 2016-07-28

### Fixes

Check results for unmatched tokens now include an executed timestamp.

API aggregates max_age now guards against check results with a `nil`
executed timestamp.

## 0.25.5 - 2016-07-12

### Fixes

Reverted the Sensu API race condition fix, it was a red herring. Desired
behaviour has been restored.

Custom check definition attributes are now included in check request
payloads, fixing check attribute token substitution for pubsub checks.

Transport connectivity issues are now handled while querying the Transport
for pipe stats for API `/info` and `/health`.

## 0.25.4 - 2016-06-20

### Fixes

Fixed a race condition bug in the Sensu API where the `@redis` and
`@transport` objects were not initialized before serving API requests.

## 0.25.3 - 2016-06-17

### Fixes

Fixed a bug in the Sensu API where it was unable to set the CORS HTTP
headers when the API had not been configured (no `"api": {}` definition).

## 0.25.2 - 2016-06-16

### Fixes

The Sensu API now responds to HEAD requests for GET routes.

The Sensu API now responds to unsupported HTTP request methods with a 404
(Not Found), i.e. PUT.

## 0.25.1 - 2016-06-14

### Fixes

The Sensu API now sets the HTTP response header "Connection" to "close".
Uchiwa was experiencing intermittent EOF errors.
[#1340](https://github.com/sensu/sensu/issues/1340)

## 0.25.0 - 2016-06-13

### Important

Sensu API legacy singular resources, e.g. `/check/:check_name`, have been
removed. Singular resources were never documented and have not been used
by most community tooling, e.g. Uchiwa, since the early Sensu releases.

### Fixes

Fixed a critical bug in Sensu client `execute_check_command()` where a
check result would contain a check command with client tokens substituted,
potentially exposing sensitive/redacted client attribute values.

### Features

The Sensu API has been rewritten to use EM HTTP Server, removing Rack and
Thin as API runtime dependencies. The API no longer uses Rack async,
making for cleaner HTTP request logic and much improved HTTP request and
response logging.

Sensu client auto de-registration on sensu-client process stop is now
supported by the Sensu client itself, no longer depending on the package
init script. The package init script de-registration functionality still
remains, but is considered to be deprecated at this time.

## 0.24.1 - 2016-06-07

### Fixes

Fixed a critical bug in Sensu server `resume()` which caused the server to
crash when querying the state of the Sensu Transport connection before it
had been initialized. [#1321](https://github.com/sensu/sensu/pull/1321)

### Other

Updated references to unmatched tokens, i.e. check result output message,
to better represent the new scope of token substitution.
[#1322](https://github.com/sensu/sensu/pull/1322)

## 0.24.0 - 2016-06-06

### Important

Sensu check ["Aggregates 2.0"](https://github.com/sensu/sensu/issues/1218)
breaks the existing Sensu API aggregate endpoints.

Sensu API GET /health endpoint, failed health checks now respond with a
`412` (preconditions failed) instead of a `503`.

### Features

Persistent Sensu event IDs, event occurrences for a client/check pair will
now have the same event ID until the event is resolved.

Added a CLI option/argument to cause the Sensu service to validate its
compiled configuration settings and exit with the appropriate exit
code, e.g. `2` for invalid. The CLI option is `--validate_config`. This
feature is now used when restarting a Sensu service to first validate the
new configuration before stopping the running service.

Improved tracking of in progress check result processing, no longer
potentially losing check results when restarting the Sensu server service.

Event data check type now explicitly defaults to "standard".

Check results for proxy clients (a.k.a JIT clients) will now have a check
"origin" set to the client name of the result producer.

Configurable Sensu Spawn concurrent child process limit (checks, mutators,
& pipe handlers). The default limit is still `12` and the EventMachine
threadpool size is automatically adjusted to accommodate a larger limit.

Sensu check ["Aggregates 2.0"](https://github.com/sensu/sensu/issues/1218).

Sensu client token substitution is now supported in every check definition
attribute value, no longer just the check command.

### Other

Sensu API GET /health endpoint, failed health check now responds with a
`412` (preconditions failed) instead of a `503`.

Sensu API POST /clients endpoint can now create clients in the registry
that are expected to produce keepalives, and validates clients with the
Sensu Settings client definition validator.

Updated Thin (used by Sensu API) to the latest version, 1.6.4.

JrJackson is now used to parse JSON when Sensu is running on JRuby.

The Sensu API now listens immediately on service start, even before it has
successfully connected to Redis and the Sensu Transport. It will now
respond with a `500` response, with a descriptive error message, when it
has not yet initialized its connections or it is reconnecting to either
Redis or the Sensu Transport. The API /info and /health endpoints will
still respond normally while reconnecting.

## 0.23.3 - 2016-05-26

### Fixes

Fixed child process write/read deadlocks when writing to STDIN or reading
from STDOUT/ERR, when the data size exceeds the pipe buffers.

Fixed child process spawn timeout deadlock, now using stdlib Timeout.

## 0.23.2 - 2016-04-25

### Fixes

Fixed client socket check result publishing when the client has a
signature. The client signature is now added to the check result payload,
making it valid.

### Other

Added client socket check result check TTL validation.

## 0.23.1 - 2016-04-15

### Other

The pure Ruby EventMachine reactor is used when running on Solaris.

## 0.23.0 - 2016-04-04

### Important

Dropped support for Rubies < 2.0.0, as they have long been EOL and have
proven to be a hindrance and security risk.

The Sensu Transport API changed. Transports are now a deferrable, they
must call `succeed()` once they have fully initialized. Sensu now waits
for its transport to fully initialize before taking other actions.

### Features

Redis Sentinel support for HA Redis. Sensu services can now be configured
to query one or more instances of Redis Sentinel for a Redis master. This
feature eliminates the last need for HAProxy in highly available Sensu
configurations. To configure Sensu services to use Redis Sentinel, hosts
and ports of one or more Sentinel instances must be provided, e.g.
`"sentinels": [{"host": "10.0.1.23", "port": 26479}]`.

Added a CLI option/argument to cause the Sensu service to print (output to
STDOUT) its compiled configuration settings and exit. The CLI option is
`--print_config` or `-P`.

Added token substitution to filter eval attributes, providing access to
event data, e.g. `"occurrences": "eval: value == :::check.occurrences:::"`.

The pure Ruby EventMachine reactor is used when running on AIX.

The Sensu 0.23 packages use Ruby 2.3.

### Other

Performance improvements. Dropped MultiJson in favour of Sensu JSON, a
lighter weight JSON parser abstraction that supports platform specific
parsers for Sensu Core and Enterprise. The Oj JSON parser is once again
used for Sensu Core. Used https://github.com/JuanitoFatas/fast-ruby and
benchmarks as a guide to further changes.

Using EventMachine 1.2.0, which brings several changes and improvements:
https://github.com/eventmachine/eventmachine/blob/master/CHANGELOG.md#1201-march-15-2016

## 0.22.2 - 2016-03-16

### Fixes

FFI library loading no longer causes a load error on AIX & Solaris.

### Other

Removed unused cruft from extension API `run()` and `safe_run()`. Optional
`options={}` was never implemented in Sensu Core and event data `dup()`
never provided the necessary protection that it claimed (only top level
hash object).

## 0.22.1 - 2016-03-01

### Other

Performance improvements. Using frozen constants for common values and
comparisons. Reduced the use of block arguments for callbacks.

Improved RabbitMQ transport channel error handling.

Fixed client signatures inspection/comparison when upgrading from a
previous release.

## 0.22.0 - 2016-01-29

### Features

Client registration events are optionally created and processed (handled,
etc.) when a client is first added to the client registry. To enable this
functionality, configure a "registration" handler definition on Sensu
server(s), or define a client specific registration handler in the client
definition, e.g. `{"client": "registration": {"handler": "debug"}}`.

Client auto de-registration on sensu-client process stop is now supported
by the Sensu package init script. Setting `CLIENT_DEREGISTER_ON_STOP=true`
and `CLIENT_DEREGISTER_HANDLER=example` in `/etc/default/sensu` will cause
the Sensu client to publish a check result to trigger the event handler
named "example", before its process stops.

Added support for Sensu client signatures, used to sign client keepalive
and check result transport messages, for the purposes of source
(publisher) verification. The client definition attribute "signature" is
used to set the client signature, e.g. `"signature": "6zvyb8lm7fxcs7yw"`.
A client signature can only be set once, the client must be deleted from
the registry before its signature can be changed or removed. Client
keepalives and check results that are not signed with the correct
signature are logged (warn) and discarded. This feature is NOT a
replacement for existing and proven security measures.

The Sensu plugin installation tool, `sensu-install`, will no longer
install a plugin if a or specified version has already been installed.

The Sensu client socket now supports UTF-8 encoding.

## 0.21.0 - 2015-11-13

### Important

Using the Sensu embedded Ruby for Sensu checks, mutators, and handlers has
become a common practice. The Sensu 0.21 packages changed the default
value of `EMBEDDED_RUBY` from `false` to `true`, allowing Sensu plugins to
use the embedded Ruby by default. This change makes it easier to get
started with Sensu.

### Features

Added a Sensu plugin installation tool, `sensu-install`, making it easier
to install Sensu community plugins. The `sensu-install` tool will use the
appropriate Ruby when installing plugins. The tool aims to produce verbose
and useful output to help when debugging plugin installation issues.

Added the Sensu API DELETE /results/:client/:check endpoint, supporting
check result deletion via the Sensu API. This feature allows users to
clean up "stale" check result data for checks that have been removed.

Added the Sensu API POST /results endpoint, supporting check result input
via the Sensu API. The JIT client feature added in 0.20 enabled this
functionality. Services that do not have access to a local Sensu client
socket can make use of this feature.

### Other

Improved the Sensu test suite to reduce the number of timeout triggered
failures. These changes make Sensu development much more pleasant.

Fixed a few inline documentation typos, e.g. sbuded -> subdued.

Moved the Sensu bins (e.g. `sensu-client`) from `bin` to `exe` to avoid
the conflict with Ruby bundler bin stubs.

Fixed Sensu API and client socket input validation, no longer accepting
multi-line values.

Fixed check request publishing for checks that make use of check
extensions, e.g. `"extension": "check_http_endpoints`.

Fixed the handler `"filters"` bug that caused Sensu to mutate handler
definitions, removing filters for successive executions.

Fixed Sensu API POST /request endpoint check request publishing to
round-robin client subscriptions.

Fixed the Windows job handle leak when spawning processes for checks.

Updated the Redis client library (em-redis-unified) to remove duplicate
Ruby hash key warnings.

## 0.20.6 - 2015-09-22

### Other

Removed the use of `EM::Iterator` from event filtering, replacing it with
`Proc` and `EM::next_tick`. `EM::Iterator` creates anonymous classes that
cannot be garbage collected on JRuby.

Removed sensu-em as a dependency, now using upstream EventMachine 1.0.8.

The Sensu API will remove a client immediately if there are no current
events for it. The API will continue to monitor the current event count
for the client to be deleted, deleting the client when there are no longer
current events or after a timeout of 5 seconds.

The Sensu API will no longer crash while fetching check result data for a
client that is being deleted.

## 0.20.5 - 2015-09-09

### Other

Updated sensu-spawn to 1.4.0, adding a mutex to ChildProcess Unix POSIX
spawn, allowing safe execution on Ruby runtimes with real threads (JRuby).

Fixed metric check output truncation when output is empty.

## 0.20.4 - 2015-08-28

### Other

Improved check output truncation. Metric check output is truncated to a
single line and 256 characters. Standard check output is not modified.

Fixed API /results endpoint, now including all results in a single
response (unless pagination is used).

Locked amq-protocol to 1.9.2, as 2.x.x does not work on older Rubies.

Fixed pipe handler output logging on JRuby.

## 0.20.3 - 2015-08-11

### Other

Improved Sensu server leader election and resignation. Changes include the
use of a unique leader ID to help guard against cases where there could be
multiple leaders.

Fixed bridge extensions; they now receive all event data, including events
that normally do not result in an action (e.g. OK check results).

## 0.20.2 - 2015-08-06

### Other

The Sensu API `/clients` route/endpoint is now capable of handling missing
client data for a client in the registry.

Sensu configuration file loading will now properly follow a link once.

## 0.20.1 - 2015-07-27

### Other

Resolving an event, that includes a check TTL, with the Sensu API will
remove the check from TTL monitoring, until another check result with a
TTL is received.

Added a timestamp to Sensu event data, recording the time of event
creation.

Fixed RabbitMQ transport connection AMQP heartbeat monitoring, the AMQP
library was sending heartbeat frames on closed connections.

The RabbitMQ transport now resets (close connection, etc.) when making
periodic reconnect attempts. The periodic reconnect timer delay will now
be incremented by 2 on every attempt, to a maximum of 20 seconds.

## 0.20.0 - 2015-07-09

### Features

Sensu services now optionally load connection and client configuration
from environment variables. This feature makes it easier to operate Sensu
in containerized environments, e.g. Docker. Sensu services read
configuration from the following variables: SENSU_TRANSPORT_NAME,
RABBITMQ_URL, REDIS_URL, SENSU_CLIENT_NAME, SENSU_CLIENT_ADDRESS,
SENSU_CLIENT_SUBSCRIPTIONS, SENSU_API_PORT

### Other

The Sensu event action is now correctly set to "create" for metric check
events.

Updated MultiJson and Childprocess to the latest versions, which include
improvements and bug fixes.

Sensu now sets the `SENSU_LOADED_TEMPFILE` environment variable to a
temporary file path, a file containing the colon delimited list of loaded
configuration files for the Sensu service
(e.g.`/tmp/sensu_client_loaded_files`). This new temporary file and
environment variable (`SENSU_LOADED_TEMPFILE`) replaced
`SENSU_CONFIG_FILES`, which has been removed, due to the exec ARG_MAX
(E2BIG) error when spawning processes after loading many configuration
files (e.g. > 2000).

## 0.19.2 - 2015-06-08

### Other

Updated sensu-em to fix UDP handlers when running on JRuby, open files
were not being closed/released properly.

## 0.19.1 - 2015-06-04

### Other

Now using an EventMachine timer for the TCP handler connection timeout, as
`pending_connect_timeout()` and `comm_inactivity_timeout()` are not
currently supported on all platforms.

Updated Thin and UUID tools to the latest versions, which include
improvements and bug fixes.

## 0.19.0 - 2015-06-01

### Features

Redis Sensu transport, a built-in alternative to the default RabbitMQ
transport. The Redis transport is currently considered experimental.
Configuring the transport name to be `redis` will enable the Redis
transport instead of RabbitMQ, e.g. `{"transport": {"name": "redis"}}`.

Round-robin client subscriptions, allowing check requests to be sent to a
single client in a subscription in a round-robin fashion. To create a
round-robin subscription, start its name with `roundrobin:` to specify the
type, e.g. "roundrobin:elasticsearch". Any check that targets the
"roundrobin:elasticsearch" subscription will have its check requests sent
to clients in a round-robin fashion.

Stale check result detection, using a defined check `ttl` and stored check
results. Sensu is now able to monitor check results, ensuring that checks
with a defined TTL (time to live) continue to be executed by clients. For
example, a standalone check could have an interval of 30 seconds and a ttl
of 50 seconds, Sensu would expect a result at least once every 50 seconds.

Check results API routes/endpoints: `/results`, `/results/:client`, and
`/results/:client/:check`. These new check result API routes/endpoints
enable new tooling, such as green light dashboards.

### Other

POSIX spawn libraries are now loaded upfront/immediately, not at child
process creation. This removes the possibility of load race conditions
when real threads are used.

Many Ruby EventMachine fixes and improvements, including FD_CLOEXEC for
the Sensu client UDP socket.

Fixed event resolution for flapping events.

Check source is now published in check requests if configured. Including
the check source in check requests fixes JIT clients for standard (pubsub)
check executions and adds context to client check execution log events.

JIT clients now have a Sensu version, set to the Sensu server version.

## 0.18.1 - 2015-05-11

### Other

Check results written to the Sensu client socket(s) now have a default
executed timestamp, equal to the current Unix/epoch time.

Check source is now validated for check results written to the Sensu
client socket(s), using the same regular expression as the configuration
attribute validator.

The latest versions of Ruby Sinatra and Async Sinatra are now used,
which include many improvements and bug fixes.

Added a caret to the beginning of API routes/endpoints that use regular
expressions, fixing a bug that caused the wrong route/endpoint to be
called, e.g. `/clients/client`.

## 0.18.0 - 2015-05-05

### Features

Dynamic (or JIT) client creation (in the registry) for check results for a
nonexistent client or a check source. Sensu clients can now monitor an
external resource on its behalf, using a check `source` to create a JIT
client for the resource, used to store the execution history and provide
context within event data. JIT client data in the registry can be
managed/updated via the Sensu API, POST `/clients`.

Storing the latest check result for every client/check pair. This data is
currently exposed via the API at `/clients/:client/history` and will be
used by several upcoming features.

The Sensu API now listens on TCP port `4567` by default.

Sensu server leader election lock timestamps now include milliseconds to
reduce the chance of a conflict when attempting to elect a new leader.

Sensu transport "reconnect_on_error" now defaults to `true`. For the
RabbitMQ transport, this means AMQP channel errors will result in a
reconnect. The Sensu transport will always reconnect when there is a loss
of connectivity.

### Other

The Sensu client sockets (TCP/UDP) are now stopped/closed before the
process is stopped.

Sensu server "master" election is now "leader" election.

Configuration file encoding is now forced to 8-bit ASCII and UTF-8 BOMs
are removed if present.

## 0.17.2 - 2015-04-08

### Other

Fixed a bug where the Sensu server was unable to stop due to the handling
event count not being decremented when events were filtered.

## 0.17.1 - 2015-03-30

### Features

Check requests can now include a check "extension" to run, instead of a
command.

### Other

Always merge check requests with local check definitions if they exist.

## 0.17.0 - 2015-03-17

### Features

Improved Sensu client keepalive event check output.

Hashed initial check request/execution scheduling splay, consistent over
process restarts/reloads.

Handler output with multiple lines is now logged as a single log event.

Support for Sensu filter extensions.

Check definitions can now specify a Sensu check extension to run,
"extension", instead of a command.

Sensu transport "reconnect_on_error" configuration option, to enable
transport reconnect in the event of an unexpected error. This is set to
false by default, as some errors are unrecoverable. The Sensu transport
will always reconnect when there is a loss of connectivity.

Sensu Redis "reconnect_on_error" configuration option, to enable Redis
reconnect in the event of an unexpected error. This is set to false by
default, as some errors are unrecoverable. The Redis client will always
reconnect when there is a loss of connectivity.

### Other

Fixed TLS/SSL on Windows.

Fixed event filtering with event action, eg. `"action": "create"`.

Restructured and documented Sensu core with YARD.

Bumped MultiJSON to 1.11.0, to make adapters read IO objects prior to
load.

## 0.16.0 - 2014-10-31

### Other

Fixed RabbitMQ transport configuration backwards compatibility.

## 0.15.0 - 2014-10-31

### Features

RabbitMQ transport now supports multiple broker connection options,
enabling connection fail-over to brokers in a cluster without
using a load balancer.

## 0.14.0 - 2014-09-29

### Features

Client socket now supports sending a result via a TCP stream. This feature
allows check results to have larger output (metrics, backtraces, etc).

API now supports CORS (configurable).

Check "source" attribute validation; it must be a string, event data
consumers no longer have to validate it.

### Other

Child process manager now supports check output larger than the max OS
buffer size. The parent process was waiting on the child to exit before
closing its write end of the pipe.

Client & server are now guarding against invalid JSON transport payloads.

## 0.13.1 - 2014-07-28

### Other

Fixed event occurrence count.

## 0.13.0 - 2014-06-12

### Non-backwards compatible changes

API GET /events now provides all event data, the same data passed to event
handlers.

AMQP handler type ("amqp") has been replaced by "transport".

Standalone check results are no longer merged with check definitions
residing on the server(s).

Removed the generic extension type.

Extension stop() no longer takes a callback, and is called when the
eventmachine reactor is stopped.

### Features

Abstracted the transport layer, opening Sensu up to alternative messaging
services.

Event bridge extension type, allowing all events to be relayed to other
services.

Client keepalives now contain the Sensu version.

Support for nested handler sets (not deep).

Setting validation reports all invalid definitions before Sensu exits.

### Other

Clients now only load instances of check extensions, and servers load
everything but check extensions.

Fixed standalone check scheduling, no longer mutating definitions.

Fixed command token substitution, allowing for the use of colons and
working value defaults.

Log events are flushed when the eventmachine reactor stops.

Dropped the Oj JSON parser, heap allocation issues and memory leaks.

Client RabbitMQ queues are no longer server named (bugs), they are now
composed of the client name, Sensu version, and the timestamp at creation.

Server master election lock updates and queries are more frequent.

## 0.12.6 - 2014-02-19

### Non-backwards compatible changes

The "profiler" extension type `Sensu::Extension::Profiler` is now "generic"
`Sensu::Extension::Generic`.

## 0.12.5 - 2014-01-20

### Other

Fixed handler severity filtering, check history is an array of strings.

## 0.12.4 - 2014-01-17

### Other

Fixed filter "eval:" on Ruby 2.1.0, and logging errors.

Fixed handler severity filtering when event action is "resolve". Events
with an action of "resolve" will be negated if the severity conditions have
not been met since the last OK status.

## 0.12.3 - 2013-12-19

### Other

The pipe handler and mutator concurrency limit is now imposed by
`EM::Worker`. A maximum of 12 processes may be spawned at a time.

## 0.12.2 - 2013-11-22

### Other

API routes now have an optional trailing slash.

RabbitMQ initial connection timeout increased from 10 to 20 seconds.

RabbitMQ connection closed errors are now rescued when attempting to
publish to an exchange, while Sensu is reconnecting.

## 0.12.1 - 2013-11-02

### Features

API GET `/stashes` now returns stash expiration information, time
remaining in seconds. eg. [{"path": "foo", "content":{"bar": "baz"},
"expire": 3598}].

### Other

Fixed a config loading bug where Sensu was not ignoring files without a
valid JSON object.

Fixed `handling event` log line data for extensions.

## 0.12.0 - 2013-10-28

### Non-backwards compatible changes

Deprecated API endpoints, `/check/request` and `/event/resolve`, have been
removed. Please use `/request` and `/resolve`.

### Features

API stashes can now expire, automatically removing themselves after `N`
seconds, eg. '{"path": "foo", "content":{"bar": "baz"}, "expire": 600}'.

### Other

Added additional AMQP library version constraints.

Improved API POST data validation.

## 0.11.3 - 2013-10-23

### Other

Fixed redacting sensitive information in log lines during configuration
loading.

Fixed AMQP library dependency version resolution.

Changed to an older version of the JSON parser, until the source of a
memory leak is identified.

## 0.11.2 - 2013-10-23

### Features

Sensu profiler extension support.

Added logger() to the extension API, providing access to the Sensu logger.

## 0.11.1 - 2013-10-16

### Other

Updated "em-redis-unified" dependency version lock, fixing Redis
reconnect when using authentication and/or select database.

## 0.11.0 - 2013-10-02

### Non-backwards compatible changes

WARNING: Extensions compatible with previous versions of Sensu will
NO LONGER FUNCTION until they are updated for Sensu 0.11.x! Extensions
are an experimental feature and not widely used.

Sensu settings are now part of the extension API & are no longer passed
as an argument to run.

TCP handlers no longer have a socket timeout, instead they have a
handler timeout for consistency.

### Features

You can specify the Sensu log severity level using the -L (--log_level)
CLI argument, providing a valid level (eg. warn).

You can specify custom sensitive Sensu client key/values to be redacted
from log events and keepalives, eg. "client": { "redact": [
"secret_access_key" ] }.

You can configure the Sensu client socket (UDP & TCP), bind & port, eg.
"client": { "socket": { "bind": "0.0.0.0", "port": 4040 } }.

Handlers & mutators can now have a timeout, in seconds.

You can configure the RabbitMQ channel prefetch value (advanced), eg.
"rabbitmq": { "prefetch": 100 }.

### Other

Sensu passes a dup of event data to mutator & handler extensions to
prevent mutation.

Extension runs are wrapped in a begin/rescue block, a safety net.

UDP handler now binds to "0.0.0.0".

Faster JSON parser.

AMQP connection heartbeats will no longer attempt to use a closed
channel.

Missing AMQP connection heartbeats will result in a reconnect.

The keepalive & result queues will now auto-delete when there are no
active consumers. This change stops the creation of a keepalive/result
backlog, stale data that may overwhelm the recovering consumers.

Improved Sensu client socket check validation.

AMQP connection will time out if the vhost is missing, there is a lack
of permissions, or authentication fails.

## 0.10.2 - 2013-07-18

### Other

Fixed redacting passwords in client data, correct value is now provided
to check command token substitution.

## 0.10.1 - 2013-07-17

### Features

You can specify multiple Sensu service configuration directories,
using the -d (--config_dir) CLI argument, providing a comma delimited
list.

A post initialize hook ("post_init()") was added to the extension API,
enabling setup (connections, etc.) within the event loop.

### Other

Catches nil exit statuses, returned from check execution.

Empty command token substitution defaults now work. eg. "-f :::bar|:::"

Specs updated to run on OS X, bash compatibility.

## 0.10.0 - 2013-06-27

### Non-backwards compatible changes

Client & check names must not contain spaces or special characters.
The valid characters are: a-z, A-Z, 0-9, "_", ".", and "-".

"command_executed" was removed from check results, as it may contain
sensitive information, such as credentials.

### Features

Passwords in client data (keepalives) and log events are replaced with
"REDACTED", reducing the possibility of exposure. The following
attributes will have their values replaced: "password", "passwd", and
"pass".

### Other

Fixed nil check status when check does not exit.

Fixed the built-in debug handler output encoding (JSON).

## 0.9.13 - 2013-05-20

### Features

The Sensu API now provides /health, an endpoint for connection & queue
monitoring. Monitor Sensu health with services like Pingdom.

Sensu clients can configure their own keepalive handler(s) & thresholds.

Command substitution tokens can have default values
(eg. :::foo.bar|default:::).

Check result (& event) data now includes "command_executed", the command
after token substitution.

### Other

Validating check results, as bugs in older Sensu clients may produce
invalid or malformed results.

Improved stale client monitoring, to better handle client deletions.

Improved check validation, names must not contain spaces or special
characters, & an "interval" is not required when "publish" is false.

## 0.9.12 - 2013-04-03

### Features

The Sensu API now provides client history, providing a list of executed
checks, their status histories, and last execution timestamps. The client
history endpoint is /clients/\<client-name\>/history, which returns a JSON
body.

The Sensu API can now bind to a specific address. To bind to an address,
use the API configuration key "bind", with a string value (eg.
"127.0.0.1").

A stop hook was added to the Sensu extension API, enabling gracefull
stop for extensions. The stop hook is called before the event loop comes
to a halt.

The Sensu client now supports check extensions, checks the run within the
Sensu Ruby VM, for aggresive service monitoring & metric collection.

### Non-backwards compatible changes

The Sensu API stashes route changed, GET /stashes now returns an array of
stash objects, with support for pagination. The API no longer uses POST
for multi-get.

Sensu services no longer have config file or directory defaults.
Configuration paths a left to packaging.

### Other

All Sensu API 201 & 202 status responses now return a body.

The Sensu server now "pauses" when reconnecting to RabbitMQ. Pausing the
Sensu server when reconnecting to RabbitMQ fixes an issue when it is also
reconnecting to Redis.

Keepalive checks now produce results with a zero exit status, fixing
keepalive check history.

Sensu runs on Ruby 2.0.0p0.

Replaced the JSON parser with a faster implementation.

Replaced the Sensu logger with a more lightweight & EventMachine
friendly implementation. No more TTY detection with colours.

Improved config validation.

## 0.9.11 - 2013-02-22

### Features

API aggregate age filter parameter.

### Non-backwards compatible changes

Removed /info "health" in favour of RabbitMQ & Redis "connected".

### Other

No longer using the default AMQP exchange or publishing directly to queues.

Removed API health filter, as the Redis connection now recovers.

Fixed config & extension directory loading on Windows.

Client socket handles non-ascii input.

## 0.9.10 - 2013-01-30

### Features

Handlers can be subdued like checks, suppression windows.

### Non-backwards compatible changes

Extensions have access to settings.

### Other

Client queue names are now determined by the broker (RabbitMQ).

Improved zombie reaping.

## 0.9.9 - 2013-01-14

### Features

RabbitMQ keepalives & results queue message and consumer counts available
via the API (/info).

Aggregate results available via the API when using a parameter
(?results=true).

Event filters; filtering events for handlers, using event attribute
matching.

TCP handler socket timeout, which defaults to 10 seconds.

Check execution timeout.

Server extensions (mutators & handlers).

### Other

Server is now using basic AMQP QoS (prefetch), just enough back pressure.

Improved check execution scheduling.

Fixed server execute command method error handling.

Events with a resolve action bypass handler severity filtering.

Check flap detection configuration validation.

## 0.9.8 - 2012-11-15

### Features

Aggregates, pooling and summarizing check results, very handy for
monitoring a horizontally scaled or distributed system.

Event handler severities, only handle events that have specific
severities.

### Other

Fixed flap detection.

Gracefully handle possible failed RabbitMQ authentication.

Catch and log AMQP channel errors, which cause the channel to close.

Fixed API event resolution handling, for events created by standalone
checks.

Minor performance improvements.

## 0.9.7 - 2012-09-20

### Features

Event data mutators, manipulate event data and its format prior to
sending to a handler.

TCP and UDP handler types, for writing event data to sockets.

API resources now support singular & plural, Rails friendly.

Client safe mode, require local check definition in order to execute
a check, disable for simpler deployment (default).

### Non-backwards compatible changes

AMQP handlers can no longer use `"send_only_check_output": true`, but
instead have access to the built-in mutators `"mutator": "only_check_output"` and
`"mutator": "only_check_output_split"`.

Ruby 1.8.7-p249 is no longer supported, as the AMQP library no longer
does. Please use the Sensu APT/YUM packages which contain an embedded
Ruby.

Client expects check requests to contain a command, be sure to upgrade
servers prior to upgrading clients.

Check subdue options have been modified, "start" is now "begin".

### Other

Improved RabbitMQ and Redis connection recovery.

Fixed API POST input validation.

Redis client connection heartbeat.

Improved graceful process termination.

Improved client socket ping/pong.

Strict dependency version locking.

Adjusted logging level for metric events.
