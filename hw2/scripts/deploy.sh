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
node_ip=
case "$2" in
  team-29-en) node_ip=10.29.0.10 ;;
  team-29-00) node_ip=10.29.0.12 ;;
  team-29-01) node_ip=10.29.0.13 ;;
esac
if [[ -n $node_ip ]]; then
  sudo -n bash -s -- "$2" "$node_ip" <<'HOSTS'
set -euo pipefail
exec 9>/run/lock/hw2-hosts.lock
flock -x 9
hosts_tmp=$(mktemp /etc/hosts.hw2.XXXXXX)
hosts_changed=false

cleanup_hosts() {
  status=$?
  trap - EXIT
  if [[ $status != 0 && $hosts_changed == true ]]; then
    cp -p "$hosts_backup" "$hosts_tmp" && mv -f -- "$hosts_tmp" /etc/hosts || status=1
    printf 'Не удалось обновить разрешение имен. Проверьте восстановление /etc/hosts из %s.\n' "$hosts_backup" >&2
  fi
  rm -f -- "$hosts_tmp"
  exit "$status"
}

trap cleanup_hosts EXIT
cp -p /etc/hosts "$hosts_tmp"
awk -v short="$1" -v fqdn="$1.hse.c.mws" -v ip="$2" '
{
  original=$0
  comment=""
  pos=index($0, "#")
  if (pos) {comment=substr($0, pos); $0=substr($0, 1, pos-1)}
  line=$1
  removed=0
  kept=0
  for (i=2; i<=NF; i++) {
    if (tolower($i) == short || tolower($i) == fqdn) removed=1
    else {line=line " " $i; kept++}
  }
  if (!removed) print original
  else if (kept) print line (comment == "" ? "" : " " comment)
  else if (comment != "") print comment
}
END {print ip " " fqdn " " short}
' /etc/hosts > "$hosts_tmp"
if ! cmp -s /etc/hosts "$hosts_tmp"; then
  hosts_backup=$(mktemp /etc/hosts.hw2-backup.XXXXXX)
  cp -p /etc/hosts "$hosts_backup"
  hosts_changed=true
  mv -f -- "$hosts_tmp" /etc/hosts
fi
for name in "$1" "$1.hse.c.mws"; do
  if ! getent ahostsv4 "$name" | awk -v ip="$2" '$1 != ip {bad=1} END {exit (NR == 0 || bad)}'; then
    printf '%s должен разрешаться только в %s.\n' "$name" "$2" >&2
    exit 1
  fi
  printf '%s -> %s\n' "$name" "$2"
done
HOSTS
fi
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
