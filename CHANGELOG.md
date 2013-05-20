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
