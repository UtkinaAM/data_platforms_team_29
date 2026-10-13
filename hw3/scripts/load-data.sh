#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HIVE_HOME=/home/team/hive-hw3
source "$HIVE_HOME/conf/hive-env.sh"
umask 077
exec 8> "$HIVE_HOME/pids/load.lock"
flock -n 8
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

cat <<'DATA' > "$work_dir/2024.csv"
1,alice,2024-03-10,login
2,bob,2024-06-15,purchase
DATA
cat <<'DATA' > "$work_dir/2025.csv"
3,carol,2025-01-20,login
4,dave,2025-08-02,purchase
DATA
cat <<'DATA' > "$work_dir/2026.csv"
5,eve,2026-02-11,login
6,frank,2026-09-18,purchase
DATA

"$HADOOP_HOME/bin/hdfs" dfs -rm -r -f /user/team/hw3/input
"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/team/hw3/input
"$HADOOP_HOME/bin/hdfs" dfs -put "$work_dir/2024.csv" "$work_dir/2025.csv" \
  "$work_dir/2026.csv" /user/team/hw3/input/

"$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false -f /dev/stdin <<'SQL'
CREATE DATABASE IF NOT EXISTS hw3;
CREATE TABLE IF NOT EXISTS hw3.events (
  id INT,
  name STRING,
  event_date STRING,
  event_type STRING
)
PARTITIONED BY (year INT)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('transactional'='false');
LOAD DATA INPATH '/user/team/hw3/input/2024.csv' OVERWRITE INTO TABLE hw3.events PARTITION (year=2024);
LOAD DATA INPATH '/user/team/hw3/input/2025.csv' OVERWRITE INTO TABLE hw3.events PARTITION (year=2025);
LOAD DATA INPATH '/user/team/hw3/input/2026.csv' OVERWRITE INTO TABLE hw3.events PARTITION (year=2026);
SHOW PARTITIONS hw3.events;
SELECT * FROM hw3.events WHERE year=2024;
SELECT * FROM hw3.events WHERE year=2025;
SELECT * FROM hw3.events WHERE year=2026;
SQL
