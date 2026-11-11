#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hw5_dir=$(cd -- "$script_dir/.." && pwd)
export AIRFLOW_HOME=/home/team/airflow-hw5
export PATH="$AIRFLOW_HOME/venv/bin:$PATH"
export AIRFLOW__CORE__LOAD_EXAMPLES=False
export AIRFLOW__CORE__EXECUTOR=SequentialExecutor
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////home/team/airflow-hw5/airflow.db
export AIRFLOW__CORE__DAGS_FOLDER="$hw5_dir/dags"
export PYTHONDONTWRITEBYTECODE=1
export SPT_NOENV=1
airflow="$AIRFLOW_HOME/venv/bin/airflow"
test -x "$airflow"
umask 077
mkdir -p "$AIRFLOW_HOME/logs" "$AIRFLOW_HOME/pids"
exec 8> "$AIRFLOW_HOME/pids/services.lock"
flock -n 8

is_service() {
  local pid=$1 role=$2
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -r /proc/$pid/environ ]] || return 1
  grep -zFxq "AIRFLOW_HOME=$AIRFLOW_HOME" "/proc/$pid/environ" || return 1
  ps -ww -p "$pid" -o user=,args= | awk -v role="$role" '
    $1 != "team" {next}
    role == "scheduler" && /airflow scheduler([[:space:]]|$)/ {found=1}
    role == "webserver-monitor" && /airflow webserver([[:space:]]|$)/ {found=1}
    role == "webserver" && /gunicorn: master \[airflow-webserver\]/ {found=1}
    role == "webserver" && /-m gunicorn.*--name airflow-webserver/ {found=1}
    END {exit !found}
  '
}

show_logs() {
  tail -n 80 "$AIRFLOW_HOME/logs/$1.log" "$AIRFLOW_HOME/logs/$1.stdout" "$AIRFLOW_HOME/logs/$1.stderr"
}

wait_for_service() {
  local service=$1 attempt pid_file="$AIRFLOW_HOME/pids/$1.pid"
  for ((attempt=0; attempt<60; attempt++)); do
    if [[ -f $pid_file ]] && is_service "$(cat "$pid_file")" "$service"; then
      if [[ $service == scheduler ]]; then
        if "$airflow" jobs check --job-type SchedulerJob --local; then
          return 0
        fi
      elif curl --fail --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/health &&
        ss -H -ltn '( sport = :8080 )' |
        awk 'NF {total++; if ($4 == "127.0.0.1:8080") local_only++} END {exit !(total == 1 && local_only == 1)}'; then
        return 0
      fi
    fi
    sleep 2
  done
  show_logs "$service"
  return 1
}

for role in scheduler webserver webserver-monitor; do
  pid_file="$AIRFLOW_HOME/pids/$role.pid"
  if [[ -f $pid_file ]] && ! is_service "$(cat "$pid_file")" "$role"; then
    rm -f -- "$pid_file"
  fi
done
for service in scheduler webserver; do
  touch "$AIRFLOW_HOME/logs/$service.log" "$AIRFLOW_HOME/logs/$service.stdout" "$AIRFLOW_HOME/logs/$service.stderr"
done
if [[ ! -f $AIRFLOW_HOME/pids/scheduler.pid ]]; then
  if ! "$airflow" scheduler -D --pid "$AIRFLOW_HOME/pids/scheduler.pid" \
    --stdout "$AIRFLOW_HOME/logs/scheduler.stdout" --stderr "$AIRFLOW_HOME/logs/scheduler.stderr" \
    --log-file "$AIRFLOW_HOME/logs/scheduler.log" 8>&- 9>&-; then
    show_logs scheduler
    exit 1
  fi
fi
wait_for_service scheduler
if [[ ! -f $AIRFLOW_HOME/pids/webserver.pid && ! -f $AIRFLOW_HOME/pids/webserver-monitor.pid ]]; then
  if ss -H -ltn '( sport = :8080 )' | grep -q .; then
    ss -ltnp '( sport = :8080 )'
    exit 1
  fi
  if ! "$airflow" webserver -D --hostname 127.0.0.1 --port 8080 --workers 1 \
    --pid "$AIRFLOW_HOME/pids/webserver.pid" --log-file "$AIRFLOW_HOME/logs/webserver.log" \
    --stdout "$AIRFLOW_HOME/logs/webserver.stdout" --stderr "$AIRFLOW_HOME/logs/webserver.stderr" \
    --access-logfile "$AIRFLOW_HOME/logs/webserver-access.log" \
    --error-logfile "$AIRFLOW_HOME/logs/webserver-error.log" 8>&- 9>&-; then
    show_logs webserver
    exit 1
  fi
fi
wait_for_service webserver
ss -ltnp '( sport = :8080 )'
