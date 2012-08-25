## 0.9.7 - TBD

### Features

Event data mutators, manipulate event data and its format prior to
sending to a handler.

TCP and UDP handler types, for writing event data to sockets.

API resources now support singular & plural, Rails friendly.

### Non-backwards compatible changes

AMQP handlers can no longer use `"send_only_check_output": true`, but
instead have access to the built-in mutators `"mutator": "only_check_output"` and
`"mutator": "only_check_output_split"`.

Ruby 1.8.7-p249 is no longer supported, as the AMQP library no longer
does. Please use the Sensu APT/YUM packages which contain an embedded
Ruby.

### Other

Improved RabbitMQ and Redis connection recovery.

Fixed API POST input validation.

Redis client connection heartbeat.

Improved graceful process termination.

Improved client socket ping/pong.

Strict dependency version locking.

Adjusted logging level for metric check results and events.
