#!/usr/bin/env bash
set -euo pipefail

hostname
whoami
[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
export SPARK_HOME=/home/team/spark-hw4
export HIVE_HOME=/home/team/hive-hw3
source "$HADOOP_CONF_DIR/hadoop-env.sh"
"$JAVA_HOME/bin/java" -version
"$SPARK_HOME/bin/spark-submit" --version
"$HADOOP_HOME/bin/hdfs" dfs -ls /
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

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

input=/user/team/hw4/input/transactions.csv
output=/user/team/hw4/output/transactions
"$HADOOP_HOME/bin/hdfs" dfs -test -f "$input"
"$HADOOP_HOME/bin/hdfs" dfs -test -d "$output"
"$HADOOP_HOME/bin/hdfs" dfs -test -f "$output/_SUCCESS"
"$HADOOP_HOME/bin/hdfs" dfs -ls "$input" "$output"
for year in 2024 2025 2026; do
  "$HADOOP_HOME/bin/hdfs" dfs -test -d "$output/year=$year"
done

"$HADOOP_HOME/bin/yarn" application -list -appTypes SPARK -appStates ALL | tee "$work_dir/applications"
awk '$1 ~ /^application_[0-9]+_[0-9]+$/ && $2 == "hw4-transform" && $3 == "SPARK" && $4 == "team"' \
  "$work_dir/applications" | LC_ALL=C sort -k1,1V | tail -n 1 | tee "$work_dir/latest-application"
awk '$6 == "FINISHED" && $7 == "SUCCEEDED" {found=1} END {exit !found}' "$work_dir/latest-application"

ss -ltn '( sport = :5433 )'
ss -H -ltn '( sport = :5433 )' | awk 'NF {found=1} END {exit !found}'
beeline=("$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false)
"${beeline[@]}" -f /dev/stdin <<'SQL'
SHOW DATABASES;
DESCRIBE FORMATTED hw4.transactions;
SHOW PARTITIONS hw4.transactions;
SQL

machine_beeline=("${beeline[@]}" --outputformat=tsv2 --showHeader=false --silent=true)
"${machine_beeline[@]}" -e 'SHOW PARTITIONS hw4.transactions;' | tee "$work_dir/partitions"
awk '
  NF {
    if ($0 !~ /^year=202[456]$/ || seen[$0]++) bad=1
    rows++
  }
  END {exit bad || rows != 3}
' "$work_dir/partitions"
for year in 2024 2025 2026; do
  "${machine_beeline[@]}" -e "SELECT id, user_name, event_date, category, amount, amount_with_fee, year FROM hw4.transactions WHERE year=$year;" |
    tee "$work_dir/data-$year"
  awk -F '\t' -v year="$year" '
    NF {
      if (NF != 7 || $7 != year) bad=1
      rows++
    }
    END {exit bad || rows != 2}
  ' "$work_dir/data-$year"
done
