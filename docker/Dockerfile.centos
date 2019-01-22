FROM centos:centos7.5.1804

LABEL vendor="Sensu Inc."
MAINTAINER Sensu Inc. "engineering@sensu.io"

ARG sensu_release=1.5.0-1

# Install Sensu
RUN echo $'[sensu]\n\
name=sensu\n\
baseurl=https://sensu.global.ssl.fastly.net/yum/$releasever/$basearch/\n\
gpgkey=https://repositories.sensuapp.org/yum/pubkey.gpg\n\
gpgcheck=1\n\
enabled=1' | tee /etc/yum.repos.d/sensu.repo

RUN yum install -y sensu-${sensu_release}.el7.x86_64

# Cleanup
RUN rm -rf /opt/sensu/embedded/lib/ruby/gems/2.4.0/{cache,doc}/* &&\
    find /opt/sensu/embedded/lib/ruby/gems/ -name "*.o" -delete

# Runtime Config
ENV CLIENT_SUBSCRIPTIONS=all,default \
    CLIENT_BIND=127.0.0.1 \
    CLIENT_DEREGISTER=true \
    # Transport & datastore
    TRANSPORT_NAME=redis \
    RABBITMQ_PORT=5672 \
    RABBITMQ_HOST=rabbitmq \
    RABBITMQ_USER=guest \
    RABBITMQ_PASSWORD=guest \
    RABBITMQ_VHOST=/ \
    RABBITMQ_PREFETCH=1 \
    RABBITMQ_SSL_SUPPORT=false \
    RABBITMQ_SSL_CERT='' \
    RABBITMQ_SSL_KEY='' \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_DB=0 \
    REDIS_AUTO_RECONNECT=true \
    REDIS_RECONNECT_ON_ERROR=false \
    # Common config
    LOG_LEVEL=warn \
    CONFIG_FILE=/etc/sensu/config.json \
    CONFIG_DIR=/etc/sensu/conf.d \
    CHECK_DIR=/etc/sensu/check.d \
    EXTENSION_DIR=/etc/sensu/extensions \
    PLUGINS_DIR=/etc/sensu/plugins \
    HANDLERS_DIR=/etc/sensu/handlers \
    # Config for gathering host metrics
    HOST_DEV_DIR=/dev \
    HOST_PROC_DIR=/proc \
    HOST_SYS_DIR=/sys \
    # Include Sensu installation embedded bin in path
    PATH=/opt/sensu/embedded/bin:$PATH \
    # Set default locale & collations
    LC_ALL=en_US.UTF-8 \
    # -W0 avoids Sensu process output to be spoiled with ruby 2.4 warnings
    RUBYOPT=-W0

EXPOSE 3030
EXPOSE 3031
EXPOSE 4567

VOLUME ["/etc/sensu/conf.d"]

CMD ["/opt/sensu/bin/sensu-client"]
