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
