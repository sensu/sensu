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
            daemon_path: "{{ salt['cmd.run'](cmd) }}"
            part: "{{ part }}"

        - require:
            - gem: sensu
        {%- if part == "sensu-dashboard" %}
            - gem: sensu-dashboard
        {%- endif %}

    {%- endif %}

{%- endfor %}
