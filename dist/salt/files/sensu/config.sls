{% import "sensu/common.jinja" as common %}
{% set hostname = salt['cmd.run']('hostname -s') %}

/var/log/sensu/:
    file:
        - directory
        - user: root
        - group: root
        - mode: 755
        - makedirs: true

/etc/sensu/:
    file:
        - directory
        - user: root
        - group: root
        - mode: 755
        - makedirs: true

{%- for part in common.sensu_parts %}
    {%- if pillar[part] %}
{{ common.config_path(hostname, part) }}:
    file:
        - managed
        - source: salt://sensu/etc/sensu/{{ common.config_filename(hostname, part) }}
        - template: jinja
        - mode: 755
        - require:
            - file: /etc/sensu/
            - file: /var/log/sensu/
    {%- endif %}
{%- endfor %}
