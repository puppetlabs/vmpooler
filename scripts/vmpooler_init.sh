#!/bin/bash
# vmpooler
# chkconfig: 345 20 80

DAEMON_PATH="/var/lib/vmpooler"

DAEMON="/usr/bin/jruby"
DAEMONOPTS="vmpooler -s Puma -E production"

NAME="vmpooler"
DESC="Provide configurable 'pools' of available (running) virtual machines"
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME

case "$1" in
start)
  printf "%-50s" "Starting $NAME..."
  cd $DAEMON_PATH
  PID=`$DAEMON $DAEMONOPTS > /dev/null 2>&1 & echo $!`
        if [ -z $PID ]; then
            printf "%s\n" "fail"
        else
            echo $PID > $PIDFILE
            printf "%s\n" "ok"
        fi
;;
status)
        printf "%-50s" "Checking $NAME..."
        if [ -f $PIDFILE ]; then
            PID=`cat $PIDFILE`
            if [ -z "`ps axf | grep ${PID} | grep -v grep`" ]; then
                printf "%s\n" "process dead but pidfile exists"
            else
                printf "%s\n" "running"
            fi
        else
            printf "%s\n" "not running"
        fi
;;
stop)
        printf "%-50s" "Stopping $NAME..."
            PID=`cat $PIDFILE`
            cd $DAEMON_PATH
        if [ -f $PIDFILE ]; then
            kill -HUP $PID
            printf "%s\n" "ok"
            rm -f $PIDFILE
        else
            printf "%s\n" "pidfile not found"
        fi
;;

restart)
    $0 stop
    $0 start
;;

*)
        echo "Usage: $0 {status|start|stop|restart}"
        exit 1
esac
