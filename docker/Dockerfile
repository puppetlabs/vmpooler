# This Dockerfile is intended to be used with the
# docker-compose file in the same directory.

FROM jruby:9.3-jdk

ENV RACK_ENV=production

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends make git && \
    apt-get clean autoclean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

COPY docker/docker-entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

COPY docker/Gemfile* ./

COPY ./ ./vmpooler-source

RUN gem install bundler && \
    bundle config set --local jobs 3 && \
    bundle install

ENTRYPOINT ["docker-entrypoint.sh"]
