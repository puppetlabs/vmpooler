# Run vmpooler in a Docker container!  Configuration can either be embedded
# and built within the current working directory, or stored in a
# VMPOOLER_CONFIG environment value and passed to the Docker daemon.
#
# BUILD:
#   docker build -t vmpooler .
#
# RUN:
#   docker run -e VMPOOLER_CONFIG -p 80:4567 -it vmpooler

FROM jruby:9.1-jdk

RUN mkdir -p /var/lib/vmpooler

WORKDIR /var/lib/vmpooler

ADD Gemfile* /var/lib/vmpooler/

COPY . /var/lib/vmpooler
COPY ./docker/docker-entrypoint.sh /usr/local/bin/

ENV LOGFILE=/dev/stdout \
      RACK_ENV=production

RUN bundle install --system ; \
      ln -s /opt/jruby/bin/jruby /usr/bin/jruby ; \
      chmod +x /usr/local/bin/docker-entrypoint.sh \
      /var/lib/vmpooler/vmpooler

ENTRYPOINT ["docker-entrypoint.sh"]
