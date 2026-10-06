#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
configs_dir="$script_dir/../configs"
hadoop_home=/home/team/hadoop-hw1
ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
test -f "$HOME/.ssh/team_internal"
test -x "$hadoop_home/bin/hdfs"
timeout 30 "$hadoop_home/bin/hdfs" dfs -test -d /

for node in team-29-en team-29-nn team-29-00 team-29-01; do
  command=(bash -s -- "$configs_dir" "$node")
  if [[ $node != team-29-en ]]; then
    ssh "${ssh_options[@]}" "team@$node" 'mkdir -p "$HOME/hw2-setup/configs"'
    scp "${ssh_options[@]}" "$configs_dir/yarn-site.xml" "$configs_dir/mapred-site.xml" \
      "team@$node:hw2-setup/configs/"
    command=(ssh "${ssh_options[@]}" "team@$node" bash -s -- /home/team/hw2-setup/configs "$node")
  fi
  "${command[@]}" <<'BASH'
set -euo pipefail
hadoop_home=/home/team/hadoop-hw1
for binary in hadoop yarn mapred; do
  test -x "$hadoop_home/bin/$binary"
done
source "$hadoop_home/etc/hadoop/hadoop-env.sh"
test -x "$JAVA_HOME/bin/jps"
version=$("$hadoop_home/bin/hadoop" version)
grep -qx 'Hadoop 3.4.2' <<< "$version"
install -d -m 755 /home/team/yarn-hw2/local /home/team/yarn-hw2/logs/containers
install -d -m 700 /home/team/yarn-hw2/logs/daemons /home/team/yarn-hw2/pids
test "$(hostname -s)" = "$2"
sed "s/@NODE_HOST@/$2/g" "$1/yarn-site.xml" > "$hadoop_home/etc/hadoop/yarn-site.xml"
install -m 644 "$1/mapred-site.xml" "$hadoop_home/etc/hadoop/mapred-site.xml"
for env in yarn-env.sh mapred-env.sh; do
  env_file="$hadoop_home/etc/hadoop/$env"
  test -f "$env_file"
  sed -i -E '/^[[:space:]]*export[[:space:]]+(HADOOP_LOG_DIR|HADOOP_PID_DIR|HADOOP_HEAPSIZE_MAX)=/d' "$env_file"
  printf 'export HADOOP_LOG_DIR="%s"\nexport HADOOP_PID_DIR="%s"\nexport HADOOP_HEAPSIZE_MAX="256m"\n' \
    "$HOME/yarn-hw2/logs/daemons" "$HOME/yarn-hw2/pids" >> "$env_file"
done
BASH
done

"$hadoop_home/bin/hdfs" dfs -mkdir -p /user/team/hw2/history/tmp \
  /user/team/hw2/history/done /user/team/hw2/staging /user/team/hw2/logs
"$hadoop_home/bin/hdfs" dfs -chmod 1777 /user/team/hw2/history/tmp /user/team/hw2/logs
"$hadoop_home/bin/hdfs" dfs -chmod 750 /user/team/hw2/history/done
"$hadoop_home/bin/hdfs" dfs -chmod 700 /user/team/hw2/staging

if [[ ! -x /usr/sbin/nginx ]]; then
  sudo -n apt-get update
  sudo -n apt-get install -y nginx
fi
sudo -n nginx -t
nginx_conf=/etc/nginx/conf.d/hw2.conf
nginx_backup=$(mktemp)
nginx_had_config=false
nginx_changed=false

restore_nginx() {
  status=$?
  trap - EXIT
  if [[ $nginx_changed == true ]]; then
    if [[ $nginx_had_config == true ]]; then
      sudo -n install -m 644 "$nginx_backup" "$nginx_conf" || status=1
    else
      sudo -n rm -f -- "$nginx_conf" || status=1
    fi
    if sudo -n nginx -t; then
      if sudo -n systemctl is-active --quiet nginx; then
        sudo -n systemctl reload nginx || status=1
      fi
    else
      status=1
    fi
    printf 'Обновление nginx прервано. Проверьте сообщения проверки и восстановления конфигурации.\n' >&2
  fi
  rm -f -- "$nginx_backup"
  exit "$status"
}

trap restore_nginx EXIT
if sudo -n test -e "$nginx_conf"; then
  sudo -n cat "$nginx_conf" > "$nginx_backup"
  nginx_had_config=true
fi
nginx_changed=true
sudo -n install -m 644 "$configs_dir/nginx-hw2.conf" "$nginx_conf"
sudo -n nginx -t
sudo -n systemctl enable nginx
if sudo -n systemctl is-active --quiet nginx; then
  sudo -n systemctl reload nginx
else
  sudo -n systemctl start nginx
fi
nginx_changed=false
rm -f -- "$nginx_backup"
trap - EXIT

bash "$script_dir/stop.sh"
bash "$script_dir/start.sh"
