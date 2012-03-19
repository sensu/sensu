{% import "sensu/common.jinja" as common %}

{%- for part in common.sensu_parts %}

    {%- if pillar[part] %}

{{ common.init_script_path(part) }}:
    file:
        - managed
        - source: salt://sensu/etc/init.d/init-template
        - template: jinja
        - mode: 755
        - defaults:
            part: "{{ part }}"

        - require:
            - gem: sensu
        {%- if part == "sensu-dashboard" %}
            - gem: sensu-dashboard
        {%- endif %}

    {%- endif %}

{%- endfor %}
