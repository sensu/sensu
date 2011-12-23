name "sensu_client"
description "sensu role for the monitoring client"
run_list(
  "recipe[sensu::client]",
  "role[sensu]"
)
