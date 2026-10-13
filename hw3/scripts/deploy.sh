#!/usr/bin/env bash
set -euo pipefail

hostname
whoami
[[ $(id -un) == team && $(hostname -s) == team-29-en ]]
umask 077
exec 9> "$HOME/.hive_hw3_deploy.lock"
flock -n 9

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export HIVE_HOME=/home/team/hive-hw3
export JAVA_HOME
java_path=$(dpkg -L openjdk-11-jre-headless | awk '/\/bin\/java$/ && !found {print; found=1}')
JAVA_HOME=$(dirname -- "$(dirname -- "$(readlink -f -- "$java_path")")")
test -x "$JAVA_HOME/bin/java"
test -f "$HADOOP_HOME/share/hadoop/common/hadoop-common-3.4.2.jar"
"$HADOOP_HOME/bin/hadoop" version
"$HADOOP_HOME/bin/hdfs" dfs -ls /
"$HADOOP_HOME/bin/yarn" node -list

ssh_options=(-i "$HOME/.ssh/team_internal" -o IdentitiesOnly=yes -o BatchMode=yes
  -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
ssh "${ssh_options[@]}" team@team-29-nn 'hostname; whoami; sudo -n true'

work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
password_file="$HOME/.hive_hw3_db_password"
if [[ ! -e $password_file ]]; then
  openssl rand -hex 32 > "$work_dir/password"
  install -m 600 "$work_dir/password" "$password_file"
fi
chmod 600 "$password_file"
db_password=$(cat "$password_file")
[[ $db_password =~ ^[0-9a-fA-F]{64}$ ]]

{
  cat <<< "$db_password"
  cat <<'REMOTE'
set -euo pipefail
[[ $(id -un) == team && $(hostname -s) == team-29-nn ]]
[[ $db_password =~ ^[0-9a-fA-F]{64}$ ]]
if ! dpkg-query -W -f='${Status}\n' postgresql 2>/dev/null | grep -qx 'install ok installed'; then
  sudo -n apt-get update
  sudo -n apt-get install -y postgresql
fi
sudo -n systemctl enable --now postgresql
config_file=$(sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -c 'SHOW config_file;')
hba_file=$(sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -c 'SHOW hba_file;')
sudo -n test -f "$config_file"
sudo -n test -f "$hba_file"
sudo -n -u postgres psql -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET listen_addresses = '10.29.0.11';
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SQL

role_exists=$(sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_roles WHERE rolname = 'hive';")
if [[ $role_exists != 1 ]]; then
  sudo -n -u postgres psql -X -v ON_ERROR_STOP=1 -c 'CREATE ROLE hive LOGIN;'
fi
sudo -n -u postgres psql -X -v ON_ERROR_STOP=1 <<SQL
SET password_encryption = 'scram-sha-256';
ALTER ROLE hive LOGIN PASSWORD '$db_password';
SQL
database_exists=$(sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_database WHERE datname = 'metastore';")
if [[ $database_exists != 1 ]]; then
  sudo -n -u postgres createdb --owner=hive metastore
fi
sudo -n -u postgres psql -X -v ON_ERROR_STOP=1 -c 'ALTER DATABASE metastore OWNER TO hive;'

sudo -n bash -s -- "$hba_file" <<'HBA'
set -euo pipefail
hba_file=$1
cp -p -- "$hba_file" "$hba_file.hw3.bak"
temporary_file=$(mktemp "${hba_file}.hw3.XXXXXX")
trap 'rm -f -- "$temporary_file"' EXIT
awk '!($1 == "host" && $2 == "metastore" && $3 == "hive" && $4 == "10.29.0.10/32")' "$hba_file" > "$temporary_file"
cat <<'RULE' >> "$temporary_file"
host metastore hive 10.29.0.10/32 scram-sha-256
RULE
chown --reference="$hba_file" "$temporary_file"
chmod --reference="$hba_file" "$temporary_file"
mv -- "$temporary_file" "$hba_file"
HBA
hba_errors=$(sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT COUNT(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;')
[[ $hba_errors == 0 ]]
sudo -n systemctl restart postgresql
systemctl status postgresql --no-pager
pg_isready -h 10.29.0.11 -p 5432
REMOTE
} | ssh "${ssh_options[@]}" team@team-29-nn "bash -c 'read -r db_password; source /dev/stdin'"

if [[ -e $HIVE_HOME ]]; then
  test -x "$HIVE_HOME/bin/hive"
  test -x "$HIVE_HOME/bin/beeline"
  test -x "$HIVE_HOME/bin/schematool"
  test -f "$HIVE_HOME/lib/hive-exec-4.0.0-alpha-2.jar"
else
  archive=apache-hive-4.0.0-alpha-2-bin.tar.gz
  curl --fail --location --retry 3 --connect-timeout 15 \
    "https://archive.apache.org/dist/hive/hive-4.0.0-alpha-2/$archive" -o "$work_dir/$archive"
  cat <<'CHECKSUM' > "$work_dir/hive.sha256"
f94c773e7ae3328d780138d9259c584e94d8f2e34715776cdfaaa78bcf3f25e1  apache-hive-4.0.0-alpha-2-bin.tar.gz
CHECKSUM
  (cd "$work_dir" && sha256sum -c hive.sha256)
  tar -xzf "$work_dir/$archive" -C "$work_dir"
  mv -- "$work_dir/apache-hive-4.0.0-alpha-2-bin" "$HIVE_HOME"
fi

driver=postgresql-42.7.4.jar
if [[ ! -f $HIVE_HOME/lib/$driver ]]; then
  curl --fail --location --retry 3 --connect-timeout 15 \
    "https://jdbc.postgresql.org/download/$driver" -o "$work_dir/$driver"
  "$JAVA_HOME/bin/jar" tf "$work_dir/$driver" > "$work_dir/driver-files"
  grep -qx 'org/postgresql/Driver.class' "$work_dir/driver-files"
  install -m 644 "$work_dir/$driver" "$HIVE_HOME/lib/$driver"
fi

mkdir -p "$HIVE_HOME/conf" "$HIVE_HOME/logs" "$HIVE_HOME/pids/native"
cat <<ENV > "$HIVE_HOME/conf/hive-env.sh"
export JAVA_HOME="$JAVA_HOME"
export HADOOP_HOME=/home/team/hadoop-hw1
export HADOOP_CONF_DIR=/home/team/hadoop-hw1/etc/hadoop
export HIVE_HOME=/home/team/hive-hw3
export HIVE_CONF_DIR=/home/team/hive-hw3/conf
export HIVE_LOG_DIR=/home/team/hive-hw3/logs
export HIVESERVER2_PID_DIR=/home/team/hive-hw3/pids/native
export HADOOP_HEAPSIZE_MAX=512
export PATH="$JAVA_HOME/bin:/home/team/hadoop-hw1/bin:\$PATH"
ENV
cat <<XML > "$work_dir/hive-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:postgresql://team-29-nn:5432/metastore</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>org.postgresql.Driver</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>hive</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>$db_password</value>
  </property>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://team-29-en:9083</value>
  </property>
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>/user/hive/warehouse</value>
  </property>
  <property>
    <name>hive.metastore.thrift.bind.host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>hive.metastore.port</name>
    <value>9083</value>
  </property>
  <property>
    <name>hive.server2.thrift.bind.host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>hive.server2.thrift.port</name>
    <value>5433</value>
  </property>
  <property>
    <name>hive.server2.authentication</name>
    <value>NONE</value>
  </property>
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.execution.engine</name>
    <value>mr</value>
  </property>
  <property>
    <name>metastore.try.direct.sql.ddl</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.strict.managed.tables</name>
    <value>false</value>
  </property>
</configuration>
XML
install -m 600 "$work_dir/hive-site.xml" "$HIVE_HOME/conf/hive-site.xml"
unset db_password
source "$HIVE_HOME/conf/hive-env.sh"

"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /tmp /user/hive/warehouse
"$HADOOP_HOME/bin/hdfs" dfs -chmod 1777 /tmp
"$HADOOP_HOME/bin/hdfs" dfs -chown team /user/hive /user/hive/warehouse
"$HADOOP_HOME/bin/hdfs" dfs -chmod 775 /user/hive /user/hive/warehouse

if ! "$HIVE_HOME/bin/schematool" -dbType postgres -info; then
  table_count=$(ssh "${ssh_options[@]}" team@team-29-nn \
    "sudo -n -u postgres psql -X -At -v ON_ERROR_STOP=1 -d metastore" <<'SQL'
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';
SQL
  )
  [[ $table_count == 0 ]]
  "$HIVE_HOME/bin/schematool" -dbType postgres -initSchema
fi
"$HIVE_HOME/bin/schematool" -dbType postgres -validate
bash "$script_dir/start.sh"
