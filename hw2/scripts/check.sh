#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
results_dir="$script_dir/../results"
hadoop_home=/home/team/hadoop-hw1
source "$hadoop_home/etc/hadoop/hadoop-env.sh"
ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
mkdir -p "$results_dir"
: > "$results_dir/jps.txt"
processes_ok=true

for node in team-29-en team-29-nn team-29-00 team-29-01; do
  if [[ $node == team-29-en ]]; then
    processes=$("$JAVA_HOME/bin/jps")
  else
    processes=$(ssh "${ssh_options[@]}" "team@$node" \
      '. "$HOME/hadoop-hw1/etc/hadoop/hadoop-env.sh" && "$JAVA_HOME/bin/jps"')
  fi
  printf '%s\n%s\n\n' "$node" "$processes" >> "$results_dir/jps.txt"
  expected=(NodeManager)
  if [[ $node == team-29-nn ]]; then
    expected=(ResourceManager JobHistoryServer)
  fi
  for class in "${expected[@]}"; do
    if ! awk -v name="$class" '$2 == name {count++} END {exit count != 1}' <<< "$processes"; then
      printf 'На %s ожидается один процесс %s.\n' "$node" "$class" >&2
      processes_ok=false
    fi
  done
done
if [[ $processes_ok != true ]]; then
  exit 1
fi

for attempt in {1..24}; do
  if timeout 30 "$hadoop_home/bin/yarn" node -list -all > "$results_dir/yarn-nodes.txt" 2>&1 &&
    awk '$1 ~ /:[0-9]+$/ {
      total++
      split($1, node, ":")
      if ($2 == "RUNNING" && node[1] ~ /^team-29-(en|00|01)$/) running[node[1]]=1
    } END {
      for (host in running) count++
      exit !(total == 3 && count == 3)
    }' \
      "$results_dir/yarn-nodes.txt"; then
    break
  fi
  if [[ $attempt == 24 ]]; then
    printf 'Ожидались ровно три NodeManager в состоянии RUNNING. Проверьте results/yarn-nodes.txt.\n' >&2
    exit 1
  fi
  sleep 5
done

: > "$results_dir/web-ui.txt"
for entry in 'ResourceManager http://team-29-nn:8088/cluster' \
  'JobHistoryServer http://team-29-nn:19888/jobhistory' \
  'ResourceManager-proxy http://10.29.0.10:8088/cluster' \
  'JobHistoryServer-proxy http://10.29.0.10:19888/jobhistory' \
  'NodeManager-en http://10.29.0.10:18042/node' \
  'NodeManager-00 http://10.29.0.10:18043/node' 'NodeManager-01 http://10.29.0.10:18044/node'; do
  read -r label url <<< "$entry"
  printf '%s: ' "$label" >> "$results_dir/web-ui.txt"
  curl -fLsS --connect-timeout 5 --max-time 10 --retry 3 --retry-connrefused \
    --retry-delay 2 -o /dev/null -w '%{http_code}\n' "$url" >> "$results_dir/web-ui.txt"
done

examples="$hadoop_home/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.2.jar"
test -f "$examples"
test_file=$(mktemp)
trap 'rm -f -- "$test_file"' EXIT
printf 'hello yarn\nhello hadoop\n' > "$test_file"
run_dir="/user/team/hw2/check-$(date -u +%Y%m%dT%H%M%S)-${test_file##*/}"
printf 'Input: %s/input\nOutput: %s/output\n' "$run_dir" "$run_dir" > "$results_dir/mapreduce-paths.txt"
"$hadoop_home/bin/hdfs" dfs -mkdir -p "$run_dir/input"
"$hadoop_home/bin/hdfs" dfs -put "$test_file" "$run_dir/input/words.txt"

timeout --kill-after=10s 600 "$hadoop_home/bin/hadoop" jar "$examples" wordcount \
  -Dmapreduce.framework.name=yarn -Dmapreduce.job.name=hw2-wordcount \
  "$run_dir/input" "$run_dir/output" \
  2>&1 | tee "$results_dir/mapreduce-job.txt"

"$hadoop_home/bin/hdfs" dfs -test -e "$run_dir/output/_SUCCESS"
"$hadoop_home/bin/hdfs" dfs -cat "$run_dir/output/part-r-*" | LC_ALL=C sort > "$results_dir/mapreduce-output.txt"
output=$(cat "$results_dir/mapreduce-output.txt")
if [[ $output != $'hadoop\t1\nhello\t2\nyarn\t1' ]]; then
  printf 'Результат wordcount не совпадает с ожидаемым.\n' >&2
  exit 1
fi

printf 'Проверка HW2 пройдена: три RUNNING NodeManager, wordcount выполнен через YARN, Web UI доступны на edge.\n'
