#!/bin/sh
set -e

set -- /var/lib/vmpooler/vmpooler "$@"

exec "$@"
