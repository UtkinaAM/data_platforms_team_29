#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hw5_dir=$(cd -- "$script_dir/.." && pwd)
export AIRFLOW_HOME=/home/team/airflow-hw5
export AIRFLOW__CORE__LOAD_EXAMPLES=False
export AIRFLOW__CORE__EXECUTOR=SequentialExecutor
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////home/team/airflow-hw5/airflow.db
export AIRFLOW__CORE__DAGS_FOLDER="$hw5_dir/dags"
export PYTHONDONTWRITEBYTECODE=1
[[ -d $AIRFLOW_HOME/pids ]] || exit 0
exec 8> "$AIRFLOW_HOME/pids/services.lock"
flock -n 8

is_service() {
  local pid=$1 role=$2
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -r /proc/$pid/environ ]] || return 1
  grep -zFxq "AIRFLOW_HOME=$AIRFLOW_HOME" "/proc/$pid/environ" || return 1
  ps -ww -p "$pid" -o user=,args= | awk -v role="$role" '
    $1 == "team" && (
      (role == "scheduler" && /airflow scheduler([[:space:]]|$)/) ||
      (role == "webserver-monitor" && /airflow webserver([[:space:]]|$)/) ||
      (role == "webserver" && (/gunicorn: master \[airflow-webserver\]/ || /-m gunicorn.*--name airflow-webserver/))
    ) {found=1}
    END {exit !found}
  '
}

stop_service() {
  local role=$1 pid attempt pid_file="$AIRFLOW_HOME/pids/$1.pid"
  [[ -f $pid_file ]] || return 0
  pid=$(cat "$pid_file")
  if is_service "$pid" "$role"; then
    if ! kill -TERM "$pid"; then
      is_service "$pid" "$role" && return 1
    fi
    for ((attempt=0; attempt<40; attempt++)); do
      is_service "$pid" "$role" || break
      sleep 1
    done
    if is_service "$pid" "$role"; then
      if ! kill -KILL "$pid"; then
        is_service "$pid" "$role" && return 1
      fi
      for ((attempt=0; attempt<10; attempt++)); do
        is_service "$pid" "$role" || break
        sleep 1
      done
      if is_service "$pid" "$role"; then
        return 1
      fi
    fi
  fi
  rm -f -- "$pid_file"
}

stop_service webserver-monitor
stop_service webserver
stop_service scheduler
