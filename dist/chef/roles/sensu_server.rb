name "sensu_server"
description "monitoring server"
run_list(
  "recipe[sensu::server]",
  "recipe[sensu::api]",
  "recipe[sensu::dashboard]",
  "role[sensu_client]"
)

override_attributes :redis => {
  :listen_addr => "0.0.0.0"
}
