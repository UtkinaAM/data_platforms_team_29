#!/usr/bin/env bash
set -euo pipefail

if [[ $(hostname -s) != team-29-en || $(id -un) != team ]]; then
  printf 'Запустите скрипт на team-29-en от пользователя team.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
archive=/tmp/hadoop-3.4.2.tar.gz
ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
test -f "$HOME/.ssh/team_internal"

if [[ ! -f $archive ]]; then
  curl -fL --retry 3 \
    https://archive.apache.org/dist/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz \
    -o "$archive.part"
  tar -tzf "$archive.part" > /dev/null
  mv -- "$archive.part" "$archive"
fi

bash "$script_dir/install-node.sh" "$archive"

for node in team-29-nn team-29-00 team-29-01; do
  ssh "${ssh_options[@]}" "team@$node" 'mkdir -p "$HOME/hw1-setup/scripts" "$HOME/hw1-setup/configs"'
  scp "${ssh_options[@]}" "$script_dir/install-node.sh" "team@$node:hw1-setup/scripts/"
  scp "${ssh_options[@]}" "$project_dir/configs/"* "team@$node:hw1-setup/configs/"
  scp "${ssh_options[@]}" "$archive" "team@$node:hw1-setup/"
  ssh "${ssh_options[@]}" "team@$node" \
    'bash "$HOME/hw1-setup/scripts/install-node.sh" "$HOME/hw1-setup/hadoop-3.4.2.tar.gz"'
done

ssh "${ssh_options[@]}" team@team-29-nn 'bash -s' <<'BASH'
set -euo pipefail
name_dir="$HOME/hdfs-hw1/name"
if [[ -f $name_dir/current/VERSION ]]; then
  printf 'NameNode уже отформатирован. Форматирование пропущено.\n'
elif [[ -n $(find "$name_dir" -mindepth 1 -print -quit) ]]; then
  printf 'Каталог NameNode не пуст, но current/VERSION отсутствует. Проверьте данные вручную.\n' >&2
  exit 1
else
  "$HOME/hadoop-hw1/bin/hdfs" namenode -format -nonInteractive
fi
BASH

bash "$script_dir/stop.sh"
bash "$script_dir/start.sh"
