#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
source "$HADOOP_CONF_DIR/hadoop-env.sh"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

cat <<'DATA' > "$work_dir/transactions.csv"
id,user_name,event_date,category,amount
1,alice,2024-03-10,books,1200.50
2,bob,2024-06-15,electronics,5400.00
3,carol,2025-01-20,books,850.00
4,dave,2025-08-02,food,2300.00
5,eve,2026-02-11,electronics,7100.00
6,frank,2026-09-18,food,1750.50
DATA

"$HADOOP_HOME/bin/hdfs" dfs -rm -r -f /user/team/hw4/input
"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/team/hw4/input
"$HADOOP_HOME/bin/hdfs" dfs -put "$work_dir/transactions.csv" /user/team/hw4/input/transactions.csv
"$HADOOP_HOME/bin/hdfs" dfs -ls /user/team/hw4/input
"$HADOOP_HOME/bin/hdfs" dfs -cat /user/team/hw4/input/transactions.csv
