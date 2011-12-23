name "sensu_dashboard"
description "sensu role for the monitoring dashboard"
run_list(
  "recipe[sensu::dashboard]",
  "role[sensu_client]"
)
