require "sensu/api/routes/settings"
require "sensu/api/routes/info"
require "sensu/api/routes/health"
require "sensu/api/routes/clients"
require "sensu/api/routes/checks"
require "sensu/api/routes/request"
require "sensu/api/routes/events"
require "sensu/api/routes/resolve"
require "sensu/api/routes/aggregates"
require "sensu/api/routes/stashes"
require "sensu/api/routes/results"
require "sensu/api/routes/silenced"

module Sensu
  module API
    module Routes
      include Settings
      include Info
      include Health
      include Clients
      include Checks
      include Request
      include Events
      include Resolve
      include Aggregates
      include Stashes
      include Results
      include Silenced

      GET_METHOD = "GET".freeze
      HEAD_METHOD = "HEAD".freeze
      POST_METHOD = "POST".freeze
      DELETE_METHOD = "DELETE".freeze
      OPTIONS_METHOD = "OPTIONS".freeze

      GET_ROUTES = [
        [SETTINGS_URI, :get_settings],
        [INFO_URI, :get_info],
        [HEALTH_URI, :get_health],
        [CLIENTS_URI, :get_clients],
        [CLIENT_URI, :get_client],
        [CLIENT_HISTORY_URI, :get_client_history],
        [CHECKS_URI, :get_checks],
        [CHECK_URI, :get_check],
        [EVENTS_URI, :get_events],
        [EVENTS_CLIENT_URI, :get_events_client],
        [EVENT_URI, :get_event],
        [AGGREGATES_URI, :get_aggregates],
        [AGGREGATE_URI, :get_aggregate],
        [AGGREGATE_CLIENTS_URI, :get_aggregate_clients],
        [AGGREGATE_CHECKS_URI, :get_aggregate_checks],
        [AGGREGATE_RESULTS_SEVERITY_URI, :get_aggregate_results_severity],
        [STASHES_URI, :get_stashes],
        [STASH_URI, :get_stash],
        [RESULTS_URI, :get_results],
        [RESULTS_CLIENT_URI, :get_results_client],
        [RESULT_URI, :get_result],
        [SILENCED_URI, :get_silenced],
        [SILENCED_ID_URI, :get_silenced_id],
        [SILENCED_SUBSCRIPTION_URI, :get_silenced_subscription],
        [SILENCED_CHECK_URI, :get_silenced_check]
      ]

      ROUTES = {
        GET_METHOD => GET_ROUTES,
        HEAD_METHOD => GET_ROUTES,
        POST_METHOD => [
          [CLIENTS_URI, :post_clients],
          [REQUEST_URI, :post_request],
          [RESOLVE_URI, :post_resolve],
          [STASHES_URI, :post_stashes],
          [STASH_URI, :post_stash],
          [RESULTS_URI, :post_results],
          [SILENCED_URI, :post_silenced],
          [SILENCED_CLEAR_URI, :post_silenced_clear]
        ],
        DELETE_METHOD => [
          [CLIENT_URI, :delete_client],
          [CHECK_URI, :delete_check],
          [EVENT_URI, :delete_event],
          [AGGREGATE_URI, :delete_aggregate],
          [STASH_URI, :delete_stash],
          [RESULT_URI, :delete_result]
        ]
      }
    end
  end
end
