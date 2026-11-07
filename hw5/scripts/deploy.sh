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
export SPARK_HOME=/home/team/spark-hw4
export HIVE_HOME=/home/team/hive-hw3
source "$HADOOP_CONF_DIR/hadoop-env.sh"
python3 --version
"$JAVA_HOME/bin/java" -version
"$HADOOP_HOME/bin/hadoop" version
"$HADOOP_HOME/bin/hdfs" dfs -ls /
"$HADOOP_HOME/bin/yarn" node -list
"$SPARK_HOME/bin/spark-submit" --version
"$HIVE_HOME/bin/hive" --version
"$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false -e 'SHOW DATABASES;'

umask 077
mkdir -p "$AIRFLOW_HOME/logs" "$AIRFLOW_HOME/pids"
exec 9> "$AIRFLOW_HOME/pids/deploy.lock"
flock -n 9
if ! dpkg-query -W -f='${Status}\n' python3-venv 2>/dev/null | grep -qx 'install ok installed'; then
  sudo -n apt-get update
  sudo -n apt-get install -y python3-venv
fi
venv="$AIRFLOW_HOME/venv"
if [[ -e $venv ]]; then
  test -x "$venv/bin/python"
else
  python3 -m venv "$venv"
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
[[ $("$venv/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') == "$PYTHON_VERSION" ]]
installed_version=$("$venv/bin/python" - <<'PY'
from importlib.metadata import PackageNotFoundError, version

try:
    print(version("apache-airflow"))
except PackageNotFoundError:
    pass
PY
)
if [[ $installed_version != 2.10.5 ]]; then
  "$venv/bin/python" -m pip install 'apache-airflow==2.10.5' \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.5/constraints-${PYTHON_VERSION}.txt"
fi
airflow="$venv/bin/airflow"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
"$airflow" version | tee "$work_dir/version"
grep -Fx '2.10.5' "$work_dir/version"
"$airflow" db migrate

password_file="$HOME/.airflow_hw5_admin_password"
if [[ ! -e $password_file ]]; then
  python3 - "$password_file" <<'PY'
from pathlib import Path
import secrets
import sys

Path(sys.argv[1]).write_text(secrets.token_urlsafe(32) + "\n")
PY
fi
chmod 600 "$password_file"
test -s "$password_file"
AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR "$airflow" users list --output json | tee "$work_dir/users"
admin_exists=$(python3 - "$work_dir/users" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    users = json.load(file)
print(sum(user["username"] == "admin" for user in users))
PY
)
[[ $admin_exists == 0 || $admin_exists == 1 ]]
if [[ $admin_exists == 0 ]]; then
  "$venv/bin/python" - "$password_file" <<'PY'
from pathlib import Path
import sys

from airflow.__main__ import main

password = Path(sys.argv[1]).read_text().strip()
if not password:
    raise ValueError("Empty admin password")
sys.argv = [
    "airflow", "users", "create", "--username", "admin", "--role", "Admin",
    "--firstname", "Team", "--lastname", "29", "--email", "team29@example.local",
    "--password", password,
]
main()
PY
fi
bash "$script_dir/start.sh"
"$airflow" version
"$airflow" dags list
"$airflow" jobs check --job-type SchedulerJob --local
ss -ltn '( sport = :8080 )'
