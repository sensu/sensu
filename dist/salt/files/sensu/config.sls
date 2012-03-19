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

/etc/sensu/config.json:
    file:
        - managed
        - source: salt://sensu/etc/sensu/config.json
        - template: jinja
        - mode: 755
        - require:
            - file: /etc/sensu/
            - file: /var/log/sensu/
