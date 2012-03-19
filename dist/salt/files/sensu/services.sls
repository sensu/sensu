{% import "sensu/common.jinja" as common %}

{%- for part in common.sensu_parts %}
    {%- if pillar[part] %}
{{ part }}:
    service:
        - running
        - require:
            - file: {{ common.init_script_path( part ) }}
        - watch:
            - file: /etc/sensu/config.json
    {%- endif %}
{%- endfor %}
