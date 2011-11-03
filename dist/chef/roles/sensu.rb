name "sensu"
description "base sensu role"

override_attributes :sensu => {
  :rabbitmq => {
    :host => "localhost",
    :password => "secret"
  },
  :redis => {
    :host => "localhost"
  },
  :api => {
    :host => "localhost"
  },
  :dashboard => {
    :host => "localhost",
    :password => "secret"
  }
}
