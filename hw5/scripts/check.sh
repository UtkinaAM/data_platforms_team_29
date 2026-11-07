#!/usr/bin/env bash
set -euo pipefail

hostname
whoami
[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hw5_dir=$(cd -- "$script_dir/.." && pwd)
export AIRFLOW_HOME=/home/team/airflow-hw5
export AIRFLOW__CORE__LOAD_EXAMPLES=False
export AIRFLOW__CORE__EXECUTOR=SequentialExecutor
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////home/team/airflow-hw5/airflow.db
export AIRFLOW__CORE__DAGS_FOLDER="$hw5_dir/dags"
export PYTHONDONTWRITEBYTECODE=1
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
export SPARK_HOME=/home/team/spark-hw4
export HIVE_HOME=/home/team/hive-hw3
source "$HADOOP_CONF_DIR/hadoop-env.sh"
airflow="$AIRFLOW_HOME/venv/bin/airflow"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
"$JAVA_HOME/bin/java" -version
"$HADOOP_HOME/bin/hadoop" version
"$SPARK_HOME/bin/spark-submit" --version 2>&1 | tee "$work_dir/spark-version"
grep -E 'version[[:space:]]+3\.5\.3([[:space:]]|$)' "$work_dir/spark-version"
"$airflow" version | tee "$work_dir/airflow-version"
grep -Fx '2.10.5' "$work_dir/airflow-version"
"$HADOOP_HOME/bin/hdfs" dfs -ls /
"$HADOOP_HOME/bin/yarn" node -list -all | tee "$work_dir/nodes"
awk '
  /^Total Nodes:/ {
    reports++
    reported=$0 ~ /^Total Nodes:[[:space:]]*3[[:space:]]*$/
  }
  $1 ~ /:[0-9]+$/ {
    total++
    split($1, node, ":")
    sub(/\..*$/, "", node[1])
    if ($2 == "RUNNING" && node[1] ~ /^team-29-(en|00|01)$/) running[node[1]]=1
  }
  END {
    for (host in running) count++
    exit !(reports == 1 && reported && total == 3 && count == 3)
  }
' "$work_dir/nodes"

"$airflow" jobs check --job-type SchedulerJob --local
curl --fail --connect-timeout 2 --max-time 10 http://127.0.0.1:8080/health
ss -ltn '( sport = :8080 )'
ss -H -ltn '( sport = :8080 )' |
  awk 'NF {total++; if ($4 == "127.0.0.1:8080") local_only++} END {exit !(total == 1 && local_only == 1)}'
"$airflow" dags list -o json | tee "$work_dir/dags"
python3 - "$work_dir/dags" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    dags = json.load(file)
raise SystemExit(sum(dag["dag_id"] == "hw5_etl" for dag in dags) != 1)
PY
"$airflow" dags list-import-errors -o json | tee "$work_dir/import-errors"
python3 - "$work_dir/import-errors" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    errors = json.load(file)
raise SystemExit(bool(errors))
PY
"$airflow" tasks list hw5_etl | tee "$work_dir/tasks"
for task in check_hdfs_input spark_transform publish_hive_table verify_hive_table; do
  grep -Fx "$task" "$work_dir/tasks"
done
test -r "$AIRFLOW_HOME/last_hw5_run_id"
run_id=$(cat "$AIRFLOW_HOME/last_hw5_run_id")
[[ $run_id =~ ^manual__hw5_[0-9]{8}T[0-9]{6}Z$ ]]
"$airflow" dags list-runs -d hw5_etl -o json | tee "$work_dir/runs"
python3 - "$work_dir/runs" "$run_id" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    runs = json.load(file)
states = [run["state"] for run in runs if run["run_id"] == sys.argv[2]]
raise SystemExit(states != ["success"])
PY
"$airflow" tasks states-for-dag-run hw5_etl "$run_id" -o json | tee "$work_dir/task-states"
python3 - "$work_dir/task-states" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    tasks = json.load(file)
expected = {"check_hdfs_input", "spark_transform", "publish_hive_table", "verify_hive_table"}
valid_tasks = len(tasks) == 4 and {task["task_id"] for task in tasks} == expected
raise SystemExit(not valid_tasks or any(task["state"] != "success" for task in tasks))
PY

"$HADOOP_HOME/bin/yarn" application -list -appTypes SPARK -appStates ALL | tee "$work_dir/applications"
awk '$1 ~ /^application_[0-9]+_[0-9]+$/ && $2 == "hw5-transform" && $3 == "SPARK" && $4 == "team"' \
  "$work_dir/applications" | LC_ALL=C sort -k1,1V | tail -n 1 | tee "$work_dir/latest-application"
awk '$6 == "FINISHED" && $7 == "SUCCEEDED" {found=1} END {exit !found}' "$work_dir/latest-application"
input=/user/team/hw5/input/transactions.csv
output=/user/team/hw5/output/transactions
"$HADOOP_HOME/bin/hdfs" dfs -test -f "$input"
"$HADOOP_HOME/bin/hdfs" dfs -test -d "$output"
"$HADOOP_HOME/bin/hdfs" dfs -test -f "$output/_SUCCESS"
"$HADOOP_HOME/bin/hdfs" dfs -ls "$input" "$output"
for year in 2024 2025 2026; do
  "$HADOOP_HOME/bin/hdfs" dfs -test -d "$output/year=$year"
done
ss -ltn '( sport = :5433 )'
ss -H -ltn '( sport = :5433 )' | awk 'NF {found=1} END {exit !found}'
beeline=("$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false)
"${beeline[@]}" -f /dev/stdin <<'SQL'
SHOW DATABASES;
DESCRIBE FORMATTED hw5.transactions;
SHOW PARTITIONS hw5.transactions;
SQL

machine_beeline=("${beeline[@]}" --outputformat=tsv2 --showHeader=false --silent=true)
"${machine_beeline[@]}" -e 'SHOW PARTITIONS hw5.transactions;' | tee "$work_dir/partitions"
awk '
  NF {
    if ($0 !~ /^year=202[456]$/ || seen[$0]++) bad=1
    rows++
  }
  END {exit bad || rows != 3}
' "$work_dir/partitions"
for year in 2024 2025 2026; do
  "${machine_beeline[@]}" -e "SELECT id, user_name, event_date, category, amount, amount_with_fee, year FROM hw5.transactions WHERE year=$year;" |
    tee "$work_dir/data-$year"
  awk -F '\t' -v year="$year" '
    NF {
      if (NF != 7 || $7 != year) bad=1
      rows++
    }
    END {exit bad || rows != 2}
  ' "$work_dir/data-$year"
done
