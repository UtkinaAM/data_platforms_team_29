#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HIVE_HOME=/home/team/hive-hw3
source "$HIVE_HOME/conf/hive-env.sh"
umask 077
mkdir -p "$HIVE_HOME/logs" "$HIVE_HOME/pids/native"
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

start_service() {
  local service=$1 class=$2 port=$3 pid='' attempt
  local pid_file="$HIVE_HOME/pids/$service.pid" log_file="$HIVE_HOME/logs/$service.log"
  if [[ -f $pid_file ]]; then
    pid=$(cat "$pid_file")
  fi
  if ! is_service; then
    rm -f -- "$pid_file"
    if ss -H -ltn "( sport = :$port )" | grep -q .; then
      ss -ltnp "( sport = :$port )"
      return 1
    fi
    if [[ $service == hiveserver2 ]]; then
      rm -f -- "$HIVESERVER2_PID_DIR/hiveserver2.pid"
    fi
    nohup "$HIVE_HOME/bin/hive" --service "$service" </dev/null >> "$log_file" 2>&1 8>&- 9>&- &
    pid=$!
    echo "$pid" > "$pid_file"
  fi
  for ((attempt=0; attempt<60; attempt++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    if is_service && ss -H -ltnp "( sport = :$port )" |
      awk -v marker="pid=$pid," 'index($0, marker) {found=1} END {exit !found}'; then
      return 0
    fi
    sleep 2
  done
  tail -n 80 "$log_file"
  return 1
}

start_service metastore org.apache.hadoop.hive.metastore.HiveMetaStore 9083
start_service hiveserver2 org.apache.hive.service.server.HiveServer2 5433
ps -ww -p "$(cat "$HIVE_HOME/pids/metastore.pid"),$(cat "$HIVE_HOME/pids/hiveserver2.pid")" -o pid,user,args
ss -ltnp '( sport = :9083 or sport = :5433 )'
