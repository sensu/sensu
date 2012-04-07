include:
    - sensu.initscripts
    - sensu.services
    - sensu.config

sensu-packages:
    pkg:
        - installed
        - names:
            - ruby
            - rubygems
            - rake
            - rabbitmq-server
            - redis-server

sensu-gems:
    gem:
        - installed
        - names:
            - sensu
{%- if pillar['sensu-dashboard'] %}
            - sensu-dashboard
{%- endif %}
