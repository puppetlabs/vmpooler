# Run vmpooler in a Docker container!  Configuration can either be embedded
# and built within the current working directory, or stored in a
# VMPOOLER_CONFIG environment value and passed to the Docker daemon.
#
# BUILD:
#   docker build -t vmpooler .
#
# RUN:
#   docker run -e VMPOOLER_CONFIG -p 80:4567 -it vmpooler

FROM jruby:1.7-jdk

RUN mkdir -p /var/lib/vmpooler
WORKDIR /var/lib/vmpooler

ADD Gemfile* /var/lib/vmpooler
RUN bundle install --system

RUN ln -s /opt/jruby/bin/jruby /usr/bin/jruby

RUN echo "deb http://httpredir.debian.org/debian jessie main" >/etc/apt/sources.list.d/jessie-main.list
RUN apt-get update
RUN apt-get install -y redis-server

COPY . /var/lib/vmpooler

ENTRYPOINT \
    /etc/init.d/redis-server start \
    && /var/lib/vmpooler/scripts/vmpooler_init.sh start \
    && while [ ! -f /var/log/vmpooler.log ]; do sleep 1; done ; \
    tail -f /var/log/vmpooler.log
