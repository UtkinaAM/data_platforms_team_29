#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
results_dir="$script_dir/../results"
hdfs="$HOME/hadoop-hw1/bin/hdfs"
source "$HOME/hadoop-hw1/etc/hadoop/hadoop-env.sh"
ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
mkdir -p "$results_dir"
: > "$results_dir/jps.txt"
processes_ok=true

for node in team-29-en team-29-nn team-29-00 team-29-01; do
  if [[ $node == team-29-en ]]; then
    processes=$("$JAVA_HOME/bin/jps")
    edge_processes=$processes
    expected=(DataNode SecondaryNameNode)
  else
    processes=$(ssh "${ssh_options[@]}" "team@$node" \
      '. "$HOME/hadoop-hw1/etc/hadoop/hadoop-env.sh" && "$JAVA_HOME/bin/jps"')
    expected=(DataNode)
    if [[ $node == team-29-nn ]]; then
      expected=(NameNode)
    fi
  fi
  printf '%s\n%s\n\n' "$node" "$processes" >> "$results_dir/jps.txt"
  for class in "${expected[@]}"; do
    if ! awk -v name="$class" '$2 == name {count++} END {exit count != 1}' <<< "$processes"; then
      printf 'На %s ожидается один процесс %s.\n' "$node" "$class" >&2
      processes_ok=false
    fi
  done
done

{
  printf 'team-29-en\n'
  if awk '$2 == "SecondaryNameNode" {found=1} END {exit !found}' <<< "$edge_processes"; then
    printf 'SecondaryNameNode работает.\n'
  else
    printf 'SecondaryNameNode не найден.\n'
  fi
  log="$HOME/hadoop-hw1/logs/hadoop-team-secondarynamenode-$(hostname -s).log"
  if [[ -f $log ]]; then
    printf '\nПоследние строки %s:\n' "$log"
    tail -n 40 "$log"
    if grep -q 'Checkpoint done' "$log"; then
      printf '\nЗаписи о checkpoint:\n'
      grep 'Checkpoint done' "$log" | tail -n 5
    else
      printf '\nCheckpoint done пока нет в логе. Повторите проверку позже.\n'
    fi
  else
    printf 'Лог Secondary NameNode пока не найден. Повторите проверку позже.\n'
  fi
} > "$results_dir/checkpoint.txt"
cat "$results_dir/checkpoint.txt"

if [[ $processes_ok != true ]]; then
  exit 1
fi

for attempt in {1..12}; do
  "$hdfs" dfsadmin -report > "$results_dir/dfsadmin-report.txt"
  if grep -Eq '^Live datanodes \(3\):?[[:space:]]*$' "$results_dir/dfsadmin-report.txt"; then
    break
  fi
  if [[ $attempt == 12 ]]; then
    printf 'Ожидалось 3 Live DataNode. Проверьте results/dfsadmin-report.txt.\n' >&2
    exit 1
  fi
  sleep 5
done

if grep -Eq '^Dead datanodes \([1-9][0-9]*\)' "$results_dir/dfsadmin-report.txt"; then
  printf 'Обнаружены Dead DataNode. Проверьте results/dfsadmin-report.txt.\n' >&2
  exit 1
fi

timeout 120 "$hdfs" dfsadmin -safemode wait
test_file=$(mktemp)
trap 'rm -f -- "$test_file"' EXIT
printf 'Hello, HDFS!\n' > "$test_file"
"$hdfs" dfs -mkdir -p /user/team/hw1
"$hdfs" dfs -put -f "$test_file" /user/team/hw1/test.txt
content=$("$hdfs" dfs -cat /user/team/hw1/test.txt)
if [[ $content != 'Hello, HDFS!' ]]; then
  printf 'Содержимое тестового файла не совпадает.\n' >&2
  exit 1
fi

timeout 120 "$hdfs" dfs -setrep -w 3 /user/team/hw1/test.txt
"$hdfs" fsck /user/team/hw1 -files -blocks -locations > "$results_dir/fsck.txt" 2>&1
if ! grep -Eq 'Status: HEALTHY|is HEALTHY' "$results_dir/fsck.txt"; then
  printf 'HDFS не имеет статуса HEALTHY. Проверьте results/fsck.txt.\n' >&2
  exit 1
fi
if ! awk '
  /^\/user\/team\/hw1\/test.txt[[:space:]]/ {test_file=1; next}
  /^\// {test_file=0}
  test_file && /Live_repl=3([^0-9]|$)/ {found=1}
  END {exit !found}
' "$results_dir/fsck.txt"; then
  printf 'Для test.txt не найдены три живые реплики. Проверьте results/fsck.txt.\n' >&2
  exit 1
fi
