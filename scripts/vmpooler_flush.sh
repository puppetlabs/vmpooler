#!/bin/bash

if [ -z "${REDIS_PW}" ]; then
  echo "redis password must be provided by setting \$REDIS_PW"
  exit 1
fi

POOLER_URL="${POOLER_URL:-vmpooler.delivery.puppetlabs.net/api/v1/config}"
REDIS_HOST="${REDIS_HOST:-vmpooler-redis-prod-2.delivery.puppetlabs.net}"

for a in $(curl "${POOLER_URL}" | grep 'name":' | awk '{print "$NF"}' | sed 's/"//g' | sed 's/,//'); do 
  for i in $(redis-cli --no-auth-warning -h "${REDIS_HOST}" -a "${REDIS_PW}" smembers vmpooler__ready__"${a}") ; do 
    redis-cli --no-auth-warning -h "${REDIS_HOST}" -a "${REDIS_PW}" smove vmpooler__ready__"${a}" vmpooler__completed__"${a}" "${i}"
  done
done
