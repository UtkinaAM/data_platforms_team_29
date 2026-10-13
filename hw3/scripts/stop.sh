#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
HIVE_HOME=/home/team/hive-hw3
[[ -d $HIVE_HOME/pids ]] || exit 0
exec 8> "$HIVE_HOME/pids/services.lock"
flock -n 8

is_service() {
  [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null &&
    ps -ww -p "$pid" -o user=,args= |
    awk -v class="$class" -v home="$HIVE_HOME" '
      $1 == "team" && index($0, class) && index($0, home) {found=1}
      END {exit !found}
    '
}

stop_service() {
  local service=$1 class=$2 pid attempt
  local pid_file="$HIVE_HOME/pids/$service.pid"
  [[ -f $pid_file ]] || return 0
  pid=$(cat "$pid_file")
  if is_service; then
    if ! kill -TERM "$pid"; then
      is_service && return 1
    fi
    for ((attempt=0; attempt<30; attempt++)); do
      is_service || break
      sleep 1
    done
    if is_service; then
      if ! kill -KILL "$pid"; then
        is_service && return 1
      fi
      for ((attempt=0; attempt<10; attempt++)); do
        is_service || break
        sleep 1
      done
      if is_service; then
        return 1
      fi
    fi
  fi
  rm -f -- "$pid_file"
}

stop_service hiveserver2 org.apache.hive.service.server.HiveServer2
stop_service metastore org.apache.hadoop.hive.metastore.HiveMetaStore
