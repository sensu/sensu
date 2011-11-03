name "sensu_client"
description "monitoring client"
run_list(
  "recipe[sensu::client]",
  "role[sensu]"
)
