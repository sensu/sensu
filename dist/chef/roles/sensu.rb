name "sensu"
description "base sensu role for attribute overrides"

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
