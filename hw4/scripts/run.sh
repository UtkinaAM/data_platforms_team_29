#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
export SPARK_HOME=/home/team/spark-hw4
export HIVE_HOME=/home/team/hive-hw3
source "$HADOOP_CONF_DIR/hadoop-env.sh"
export PYSPARK_PYTHON=python3
input=hdfs://team-29-nn:9000/user/team/hw4/input/transactions.csv
output=hdfs://team-29-nn:9000/user/team/hw4/output/transactions
"$HADOOP_HOME/bin/hdfs" dfs -test -f "$input"
exec 9> "$SPARK_HOME/.hw4-run.lock"
flock -n 9

"$SPARK_HOME/bin/spark-submit" \
  --master yarn \
  --deploy-mode client \
  --driver-memory 512m \
  --executor-memory 512m \
  --executor-cores 1 \
  --num-executors 2 \
  --conf spark.yarn.am.memory=256m \
  --conf spark.driver.host=10.29.0.10 \
  --conf spark.driver.bindAddress=0.0.0.0 \
  --conf spark.sql.shuffle.partitions=3 \
  "$script_dir/spark_job.py" "$input" "$output"

"$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false -f /dev/stdin <<'SQL'
CREATE DATABASE IF NOT EXISTS hw4;
CREATE EXTERNAL TABLE IF NOT EXISTS hw4.transactions (
  id INT,
  user_name STRING,
  event_date DATE,
  category STRING,
  amount DOUBLE,
  amount_with_fee DOUBLE
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION 'hdfs://team-29-nn:9000/user/team/hw4/output/transactions';
MSCK REPAIR TABLE hw4.transactions;
SHOW PARTITIONS hw4.transactions;
SELECT * FROM hw4.transactions WHERE year=2024;
SELECT * FROM hw4.transactions WHERE year=2025;
SELECT * FROM hw4.transactions WHERE year=2026;
SQL
