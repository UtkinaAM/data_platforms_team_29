#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -un) != team ]]; then
  printf 'Запустите скрипт от пользователя team.\n' >&2
  exit 1
fi

if [[ $# -ne 1 || ! -f $1 ]]; then
  printf 'Использование: bash install-node.sh /tmp/hadoop-3.4.2.tar.gz\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
configs_dir="$script_dir/../configs"
archive=$1
hadoop_home="$HOME/hadoop-hw1"

for config in core-site.xml hdfs-site.xml workers; do
  test -f "$configs_dir/$config"
done

sudo -n apt-get update
if ! LC_ALL=C apt-cache policy openjdk-11-jdk | awk '$1 == "Candidate:" && $2 != "(none)" {found=1} END {exit !found}'; then
  sudo -n apt-get install -y software-properties-common
  sudo -n add-apt-repository -y universe
  sudo -n apt-get update
fi
sudo -n apt-get install -y openjdk-11-jdk
javac_path=$(dpkg -L openjdk-11-jdk-headless | awk '/\/bin\/javac$/ {print; exit}')
java_home=$(dirname -- "$(dirname -- "$(readlink -f -- "$javac_path")")")
test -x "$java_home/bin/java"
test -x "$java_home/bin/jps"

if [[ -e $hadoop_home ]]; then
  if [[ ! -x $hadoop_home/bin/hadoop || ! -x $hadoop_home/bin/hdfs ||
        ! -f $hadoop_home/share/hadoop/common/hadoop-common-3.4.2.jar ]]; then
    printf 'В %s найдена неполная установка или другая версия Hadoop. Проверьте ее вручную.\n' "$hadoop_home" >&2
    exit 1
  fi
else
  tar -tzf "$archive" > /dev/null
  mkdir -p "$hadoop_home"
  tar -xzf "$archive" -C "$hadoop_home" --strip-components=1
fi

mkdir -p "$HOME/hdfs-hw1/name" "$HOME/hdfs-hw1/data" \
  "$HOME/hdfs-hw1/checkpoint" "$hadoop_home/pids"

for config in core-site.xml hdfs-site.xml workers; do
  install -m 644 "$configs_dir/$config" "$hadoop_home/etc/hadoop/$config"
done

env_file="$hadoop_home/etc/hadoop/hadoop-env.sh"
test -f "$env_file"
sed -i -E '/^[[:space:]]*export[[:space:]]+(JAVA_HOME|HADOOP_PID_DIR)=/d' "$env_file"
printf 'export JAVA_HOME="%s"\nexport HADOOP_PID_DIR="%s"\n' \
  "$java_home" "$hadoop_home/pids" >> "$env_file"

version=$("$hadoop_home/bin/hadoop" version)
printf '%s\n' "$version"
if ! grep -qx 'Hadoop 3.4.2' <<< "$version"; then
  printf 'Ожидался Hadoop 3.4.2.\n' >&2
  exit 1
fi
