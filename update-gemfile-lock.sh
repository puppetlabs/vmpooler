#!/usr/bin/env bash

docker run -it --rm \
  -v $(pwd):/app \
  $(grep ^FROM docker/Dockerfile |cut -d ' ' -f2) \
  /bin/bash -c 'cd /app && gem install bundler && bundle lock --update; echo "LOCK_FILE_UPDATE_EXIT_CODE=$?"'
