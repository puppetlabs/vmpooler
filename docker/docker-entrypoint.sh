#!/bin/sh
set -e

set -- bundle exec vmpooler "$@"

exec "$@"
