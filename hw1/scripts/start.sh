#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

for entry in 'team-29-nn namenode NameNode' \
  'team-29-00 datanode DataNode' 'team-29-01 datanode DataNode' \
  'team-29-en datanode DataNode' 'team-29-en secondarynamenode SecondaryNameNode'; do
  read -r node daemon class <<< "$entry"
  command=(bash -s -- "$daemon" "$class")
  if [[ $node != team-29-en ]]; then
    command=(ssh "${ssh_options[@]}" "team@$node" "${command[@]}")
  fi
  "${command[@]}" <<'BASH'
set -euo pipefail
source "$HOME/hadoop-hw1/etc/hadoop/hadoop-env.sh"
processes=$("$JAVA_HOME/bin/jps")
if awk -v name="$2" '$2 == name {found=1} END {exit !found}' <<< "$processes"; then
  printf '%s на %s уже работает.\n' "$2" "$(hostname -s)"
else
  "$HOME/hadoop-hw1/bin/hdfs" --daemon start "$1"
fi
BASH
done
