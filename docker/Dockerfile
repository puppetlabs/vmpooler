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

COPY ./docker/docker-entrypoint.sh /usr/local/bin/

ENV LOGFILE=/dev/stdout \
      RACK_ENV=production

RUN gem install vmpooler && \
      chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["vmpooler"]
