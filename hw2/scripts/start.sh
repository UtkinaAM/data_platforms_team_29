#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

for entry in 'team-29-nn yarn resourcemanager ResourceManager' \
  'team-29-nn mapred historyserver JobHistoryServer' \
  'team-29-en yarn nodemanager NodeManager' \
  'team-29-00 yarn nodemanager NodeManager' 'team-29-01 yarn nodemanager NodeManager'; do
  read -r node binary daemon class <<< "$entry"
  command=(bash -s -- "$binary" "$daemon" "$class")
  if [[ $node != team-29-en ]]; then
    command=(ssh "${ssh_options[@]}" "team@$node" "${command[@]}")
  fi
  "${command[@]}" <<'BASH'
set -euo pipefail
source "$HOME/hadoop-hw1/etc/hadoop/hadoop-env.sh"
processes=$("$JAVA_HOME/bin/jps")
if awk -v name="$3" '$2 == name {found=1} END {exit !found}' <<< "$processes"; then
  printf '%s на %s уже работает.\n' "$3" "$(hostname -s)"
else
  "$HOME/hadoop-hw1/bin/$1" --daemon start "$2"
fi
BASH
done
