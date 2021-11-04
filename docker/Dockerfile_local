# Run vmpooler in a Docker container!  Configuration can either be embedded
# and built within the current working directory, or stored in a
# VMPOOLER_CONFIG environment value and passed to the Docker daemon.
#
# BUILD:
#   docker build -t vmpooler .
#
# RUN:
#   docker run -e VMPOOLER_CONFIG -p 80:4567 -it vmpooler

FROM jruby:9.2-jdk

ENV RACK_ENV=production

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends make && \
    apt-get clean autoclean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

COPY docker/docker-entrypoint.sh /usr/local/bin/
COPY ./Gemfile ./
COPY ./vmpooler.gemspec ./
COPY ./lib/vmpooler/version.rb ./lib/vmpooler/version.rb

RUN gem install bundler && \
    bundle config set --local jobs 3 && \
    bundle install

COPY ./ ./

RUN gem build vmpooler.gemspec && \
    gem install vmpooler*.gem && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
