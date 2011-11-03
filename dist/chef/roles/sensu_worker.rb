name "sensu_worker"
description "monitoring worker"
run_list(
  "recipe[sensu::worker]",
  "role[sensu_client]"
)
