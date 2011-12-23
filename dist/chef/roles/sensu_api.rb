name "sensu_api"
description "sensu role for the monitoring api"
run_list(
  "recipe[sensu::api]",
  "role[sensu_client]"
)
