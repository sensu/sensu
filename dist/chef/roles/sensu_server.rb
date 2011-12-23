name "sensu_server"
description "sensu role for the monitoring server"
run_list(
  "recipe[sensu::server]",
  "role[sensu_client]"
)
