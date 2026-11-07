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
airflow="$AIRFLOW_HOME/venv/bin/airflow"
umask 077
exec 9> "$AIRFLOW_HOME/pids/run.lock"
flock -n 9
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
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
"$airflow" dags unpause hw5_etl
run_id="manual__hw5_$(date -u +%Y%m%dT%H%M%SZ)"
"$airflow" dags trigger -r "$run_id" hw5_etl
cat <<< "$run_id" > "$work_dir/run_id"
mv -- "$work_dir/run_id" "$AIRFLOW_HOME/last_hw5_run_id"

state=''
deadline=$((SECONDS+1800))
while ((SECONDS < deadline)); do
  timeout 30 "$airflow" dags list-runs -d hw5_etl -o json | tee "$work_dir/runs"
  state=$(python3 - "$work_dir/runs" "$run_id" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    runs = json.load(file)
states = [run["state"] for run in runs if run["run_id"] == sys.argv[2]]
if len(states) > 1:
    raise ValueError("Duplicate run_id")
print(states[0] if states else "")
PY
  )
  case $state in
    success|failed) break ;;
    queued|running|'') sleep 5 ;;
    *) exit 1 ;;
  esac
done
"$airflow" dags list-runs -d hw5_etl
"$airflow" tasks states-for-dag-run hw5_etl "$run_id"
[[ $state == success ]]
