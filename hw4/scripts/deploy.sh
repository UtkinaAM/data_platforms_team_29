#!/usr/bin/env bash
set -euo pipefail

hostname
whoami
[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
export SPARK_HOME=/home/team/spark-hw4
source "$HADOOP_CONF_DIR/hadoop-env.sh"
"$JAVA_HOME/bin/java" -version
command -v python3
test -f "$HADOOP_HOME/share/hadoop/common/hadoop-common-3.4.2.jar"
"$HADOOP_HOME/bin/hdfs" dfs -ls /
"$HADOOP_HOME/bin/yarn" node -list

umask 077
exec 9> "$HOME/.spark_hw4_deploy.lock"
flock -n 9
if [[ -e $SPARK_HOME ]]; then
  test -x "$SPARK_HOME/bin/spark-submit"
  test -f "$SPARK_HOME/jars/spark-core_2.12-3.5.3.jar"
else
  work_dir=$(mktemp -d)
  trap 'rm -rf -- "$work_dir"' EXIT
  archive=spark-3.5.3-bin-hadoop3.tgz
  base_url=https://archive.apache.org/dist/spark/spark-3.5.3
  curl --fail --location --retry 3 --connect-timeout 15 \
    "$base_url/$archive" -o "$work_dir/$archive"
  curl --fail --location --retry 3 --connect-timeout 15 \
    "$base_url/$archive.sha512" -o "$work_dir/$archive.sha512"
  (cd "$work_dir" && sha512sum -c "$archive.sha512")
  tar -xzf "$work_dir/$archive" -C "$work_dir"
  mv -- "$work_dir/spark-3.5.3-bin-hadoop3" "$SPARK_HOME"
fi

"$SPARK_HOME/bin/spark-submit" --version
"$HADOOP_HOME/bin/hdfs" dfs -ls /
"$HADOOP_HOME/bin/yarn" node -list -all
