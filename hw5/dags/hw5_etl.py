from datetime import timedelta
from pathlib import Path
from shlex import quote

import pendulum
from airflow import DAG
from airflow.operators.bash import BashOperator


hw5_dir = Path(__file__).resolve().parents[1]
environment = {
    "HADOOP_HOME": "/home/team/hadoop-hw1",
    "HADOOP_CONF_DIR": "/home/team/hadoop-hw1/etc/hadoop",
    "YARN_CONF_DIR": "/home/team/hadoop-hw1/etc/hadoop",
    "SPARK_HOME": "/home/team/spark-hw4",
    "HIVE_HOME": "/home/team/hive-hw3",
    "PYSPARK_PYTHON": "/usr/bin/python3",
}
bash_prefix = 'set -euo pipefail\nsource "$HADOOP_CONF_DIR/hadoop-env.sh"\n'
spark_job = quote(str(hw5_dir / "scripts" / "spark_job.py"))

with DAG(
    dag_id="hw5_etl",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule=None,
    catchup=False,
    is_paused_upon_creation=False,
    tags=["hw5", "spark", "yarn"],
    max_active_runs=1,
    max_active_tasks=1,
    dagrun_timeout=timedelta(minutes=25),
    default_args={
        "owner": "team",
        "env": environment,
        "append_env": True,
        "cwd": "/home/team/airflow-hw5",
        "do_xcom_push": False,
        "skip_on_exit_code": None,
        "execution_timeout": timedelta(minutes=15),
    },
) as dag:
    check_hdfs_input = BashOperator(
        task_id="check_hdfs_input",
        bash_command=bash_prefix + """
"$HADOOP_HOME/bin/hdfs" dfs -test -f /user/team/hw5/input/transactions.csv
"$HADOOP_HOME/bin/hdfs" dfs -ls /user/team/hw5/input/transactions.csv
""",
    )

    spark_transform = BashOperator(
        task_id="spark_transform",
        bash_command=bash_prefix + f"""
"$SPARK_HOME/bin/spark-submit" \
  --master yarn \
  --deploy-mode client \
  --driver-memory 512m \
  --executor-memory 512m \
  --executor-cores 1 \
  --num-executors 2 \
  --conf spark.yarn.am.memory=256m \
  --conf spark.driver.host=10.29.0.10 \
  --conf spark.driver.bindAddress=0.0.0.0 \
  --conf spark.sql.shuffle.partitions=3 \
  {spark_job} \
  hdfs://team-29-nn:9000/user/team/hw5/input/transactions.csv \
  hdfs://team-29-nn:9000/user/team/hw5/output/transactions
""",
    )

    publish_hive_table = BashOperator(
        task_id="publish_hive_table",
        bash_command=bash_prefix + """
"$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false -f /dev/stdin <<'SQL'
CREATE DATABASE IF NOT EXISTS hw5;
CREATE EXTERNAL TABLE IF NOT EXISTS hw5.transactions (
  id INT,
  user_name STRING,
  event_date DATE,
  category STRING,
  amount DOUBLE,
  amount_with_fee DOUBLE
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION 'hdfs://team-29-nn:9000/user/team/hw5/output/transactions';
MSCK REPAIR TABLE hw5.transactions;
SQL
""",
    )

    verify_hive_table = BashOperator(
        task_id="verify_hive_table",
        bash_command=bash_prefix + """
"$HIVE_HOME/bin/beeline" -u jdbc:hive2://team-29-en:5433/default -n team -p '' --force=false -f /dev/stdin <<'SQL'
SHOW PARTITIONS hw5.transactions;
SELECT * FROM hw5.transactions WHERE year=2024;
SELECT * FROM hw5.transactions WHERE year=2025;
SELECT * FROM hw5.transactions WHERE year=2026;
SQL
""",
    )

    check_hdfs_input >> spark_transform >> publish_hive_table >> verify_hive_table
