{% import "sensu/common.jinja" as common %}
{% set hostname = salt['cmd.run']('hostname -s') %}

{%- for part in common.sensu_parts %}
    {%- if pillar[part] %}
{{ part }}:
    service:
        - running
        - require:
            - file: {{ common.init_script_path( part ) }}
        - watch:
            - file: {{ common.config_path(hostname, part) }}
    {%- endif %}
{%- endfor %}
