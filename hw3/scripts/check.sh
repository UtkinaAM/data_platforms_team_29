#!/usr/bin/env bash
set -euo pipefail

hostname
whoami
[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
export HIVE_HOME=/home/team/hive-hw3
source "$HIVE_HOME/conf/hive-env.sh"
java -version
"$HADOOP_HOME/bin/hadoop" version
"$HIVE_HOME/bin/hive" --version
"$HADOOP_HOME/bin/hdfs" dfs -ls /user/hive
"$HADOOP_HOME/bin/hdfs" dfs -ls /user/hive/warehouse

ssh -i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new team@team-29-nn 'bash -s' <<'REMOTE'
set -euo pipefail
systemctl status postgresql --no-pager
pg_isready -h 10.29.0.11 -p 5432
REMOTE
"$HIVE_HOME/bin/schematool" -dbType postgres -info
"$HIVE_HOME/bin/schematool" -dbType postgres -validate

for service in metastore hiveserver2; do
  pid=$(cat "$HIVE_HOME/pids/$service.pid")
  [[ $pid =~ ^[1-9][0-9]*$ ]]
  if [[ $service == metastore ]]; then
    class=org.apache.hadoop.hive.metastore.HiveMetaStore
    port=9083
  else
    class=org.apache.hive.service.server.HiveServer2
    port=5433
  fi
  ps -ww -p "$pid" -o pid,user,args
  ps -ww -p "$pid" -o user=,args= |
    awk -v class="$class" -v home="$HIVE_HOME" '
      $1 == "team" && index($0, class) && index($0, home) {found=1}
      END {exit !found}
    '
  ss -ltnp "( sport = :$port )"
  ss -H -ltnp "( sport = :$port )" |
    awk -v marker="pid=$pid," 'index($0, marker) {found=1} END {exit !found}'
done

beeline=("$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false)
"${beeline[@]}" -f /dev/stdin <<'SQL'
SHOW DATABASES;
DESCRIBE FORMATTED hw3.events;
SHOW PARTITIONS hw3.events;
SELECT year, COUNT(*) FROM hw3.events GROUP BY year ORDER BY year;
SELECT * FROM hw3.events ORDER BY year, id;
SQL

umask 077
work_dir=$(mktemp -d)
pid1=''
pid2=''
cleanup() {
  local client_pid
  for client_pid in "$pid1" "$pid2"; do
    if [[ -n $client_pid ]]; then
      kill -TERM "$client_pid" 2>/dev/null || true
      wait "$client_pid" || true
    fi
  done
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
machine_beeline=("${beeline[@]}" --outputformat=tsv2 --showHeader=false --silent=true)
"${machine_beeline[@]}" -e 'SHOW PARTITIONS hw3.events;' | tee "$work_dir/partitions"
awk '
  NF {
    if ($0 !~ /^year=202[456]$/ || seen[$0]++) bad=1
    rows++
  }
  END {exit bad || rows != 3}
' "$work_dir/partitions"
"${machine_beeline[@]}" -e 'SELECT year, COUNT(*) FROM hw3.events GROUP BY year ORDER BY year;' |
  tee "$work_dir/counts"
awk -F '\t' '
  NF {
    if (NF != 2 || $1 !~ /^202[456]$/ || $2 != 2 || seen[$1]++) bad=1
    rows++
  }
  END {exit bad || rows != 3}
' "$work_dir/counts"

client1=$(mktemp "$work_dir/client1.XXXXXX")
client2=$(mktemp "$work_dir/client2.XXXXXX")
"${machine_beeline[@]}" -e 'SELECT COUNT(*) FROM hw3.events WHERE year=2024;' > "$client1" 2>&1 &
pid1=$!
"${machine_beeline[@]}" -e 'SELECT COUNT(*) FROM hw3.events WHERE year=2025;' > "$client2" 2>&1 &
pid2=$!
if wait "$pid1"; then
  status1=0
else
  status1=$?
fi
pid1=''
if wait "$pid2"; then
  status2=0
else
  status2=$?
fi
pid2=''
cat "$client1"
cat "$client2"
count_status=0
for client_file in "$client1" "$client2"; do
  if ! awk '
    /^[[:space:]]*[0-9]+[[:space:]]*$/ {rows++; if ($1 != 2) bad=1}
    END {exit bad || rows != 1}
  ' "$client_file"; then
    count_status=1
  fi
done
rm -f -- "$client1" "$client2"
[[ $status1 == 0 && $status2 == 0 && $count_status == 0 ]]
