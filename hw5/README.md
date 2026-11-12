# ДЗ5. Введение в платформы данных

Airflow управляет обработкой заранее загруженного CSV из HDFS. DAG запускает существующий Spark через YARN, сохраняет преобразованные данные в Parquet и создает external table в Hive. Результат читается через стандартный клиент Beeline.

## Участники

| ФИО | Telegram | GitHub |
| --- | --- | --- |
| Соленникова София Сергеевна | @an_soc | [poskrebish](https://github.com/poskrebish) |
| Маликова Полина Михайловна | @pomalkv | [pmmalikova](https://github.com/pmmalikova) |
| Пушкарева Анастасия Эдуардовна | @nonetrait | [nonetrait](https://github.com/nonetrait) |
| Уткина Анастасия Михайловна | @aytsantu | [UtkinaAM](https://github.com/UtkinaAM) |

## Архитектура

Airflow устанавливается на edge `team-29-en` и работает на одном сервере с SQLite и `SequentialExecutor`. Scheduler запускает задачи по очереди, webserver предоставляет интерфейс на `127.0.0.1:8080`.

```text
Предварительно загруженный CSV в HDFS
    -> Airflow DAG hw5_etl
    -> проверка input
    -> Spark через YARN, трансформации DataFrame
    -> Parquet в HDFS с партициями year
    -> Hive external table
    -> Beeline
```

Spark driver работает на edge в режиме `client`. YARN запускает два Spark executor на NodeManager `team-29-en`, `team-29-00` и `team-29-01`. Используются HDFS из ДЗ1, YARN из ДЗ2, Hive из ДЗ3 и Spark из ДЗ4. Отдельный Spark Master не запускается.

Таблица создается через существующий HiveServer2 `team-29-en:5433`. Spark напрямую к Hive Metastore не подключается.

## Среда

- Ubuntu 24.04.5 LTS и системный Python 3;
- OpenJDK 11;
- Hadoop 3.4.2;
- Apache Spark 3.5.3;
- Apache Hive 4.0.0-alpha-2;
- Apache Airflow 2.10.5;
- пользователь `team`.

| Компонент | Путь |
| --- | --- |
| Hadoop | `/home/team/hadoop-hw1` |
| Spark | `/home/team/spark-hw4` |
| Hive | `/home/team/hive-hw3` |
| Airflow | `/home/team/airflow-hw5` |
| Виртуальное окружение Airflow | `/home/team/airflow-hw5/venv` |
| База метаданных | `/home/team/airflow-hw5/airflow.db` |

DAG читается из `hw5/dags` текущего клона репозитория. Логи, PID-файлы, виртуальное окружение, база метаданных и ID последнего запуска находятся вне репозитория, в `AIRFLOW_HOME`.

## Структура проекта

```text
hw5/
├── README.md
├── dags/
│   └── hw5_etl.py
└── scripts/
    ├── deploy.sh
    ├── start.sh
    ├── stop.sh
    ├── load-data.sh
    ├── run.sh
    ├── spark_job.py
    └── check.sh
```

- `deploy.sh`: проверка окружения, установка Airflow в виртуальное окружение, подготовка базы метаданных и пользователя admin.
- `start.sh` и `stop.sh`: запуск и остановка scheduler и webserver по PID-файлам.
- `load-data.sh`: предварительная загрузка CSV в HDFS.
- `run.sh`: запуск DAG через scheduler и ожидание результата.
- `spark_job.py`: преобразования DataFrame и запись Parquet.
- `check.sh`: автоматическая проверка Airflow, YARN, HDFS и данных в Hive.

## Развертывание

Команды выполняются на `team-29-en` от пользователя `team`. HDFS, YARN, Spark и Hive должны быть готовы к работе.

```bash
ssh team@2.59.82.111
```

В уже клонированном репозитории:

```bash
cd ~/data_platforms_team_29
git pull origin main
cd hw5
bash scripts/deploy.sh
```

`deploy.sh` проверяет окружение, создает отдельное виртуальное окружение и устанавливает Airflow 2.10.5 с официальным constraints-файлом для текущей версии Python. Если нужен пакет `python3-venv`, скрипт устанавливает его через `sudo` без запроса пароля.

Затем выполняется `airflow db migrate`, создается пользователь `admin` с ролью `Admin` и запускаются scheduler и webserver с одним рабочим процессом. При повторном развертывании сохраняются виртуальное окружение, база метаданных и существующий пользователь.

Случайный пароль admin хранится только на edge в `$HOME/.airflow_hw5_admin_password` с правами `600`. При повторном запуске используется тот же файл.

## Запуск и остановка Airflow

Из каталога `hw5` выполнить:

```bash
bash scripts/start.sh
```

`start.sh` проверяет PID-файлы, не дублирует работающие сервисы и ждет готовности scheduler и webserver. Логи находятся в `/home/team/airflow-hw5/logs`, PID-файлы в `/home/team/airflow-hw5/pids`.

Остановка:

```bash
bash scripts/stop.sh
```

Останавливаются только scheduler и webserver HW5, включая его Gunicorn monitor.

## Загрузка исходных данных

Этот шаг выполняется до запуска DAG:

```bash
bash scripts/load-data.sh
```

Скрипт создает временный CSV из шести строк с полями `id`, `user_name`, `event_date`, `category`, `amount` и загружает его в `/user/team/hw5/input/transactions.csv`. На каждый год, 2024, 2025 и 2026, приходится по две записи.

Повторный запуск пересоздает только `/user/team/hw5/input`. Сам DAG исходный CSV не загружает: Spark читает уже подготовленный файл из HDFS.

## Запуск DAG

```bash
bash scripts/run.sh
```

Скрипт проверяет scheduler, webserver, наличие DAG и отсутствие ошибок импорта DAG. Затем снимает паузу с `hw5_etl` и запускает DAG через `airflow dags trigger`. ID запуска сохраняется в `/home/team/airflow-hw5/last_hw5_run_id`.

`run.sh` ждет именно этот запуск DAG до 30 минут, после чего показывает его состояние и состояния задач. Если запуск завершился с ошибкой или превышено время ожидания, скрипт возвращает ненулевой код.

DAG запускается вручную, без расписания и catchup. Одновременно выполняется один запуск DAG. В нем четыре последовательные задачи:

1. `check_hdfs_input` проверяет наличие исходного файла в HDFS и показывает его через `hdfs dfs -ls`.
2. `spark_transform` запускает Spark через `--master yarn --deploy-mode client`. Driver и два executor используют по `512m` памяти, каждый executor получает одно ядро. Driver доступен по `10.29.0.10`.
3. `publish_hive_table` создает через Beeline базу `hw5`, external table `hw5.transactions` и добавляет партиции через `MSCK REPAIR TABLE`.
4. `verify_hive_table` показывает партиции и читает данные каждого года через Beeline. Результат можно посмотреть в логах задачи Airflow.

Spark читает CSV как строки, явно преобразует `id` в `INT`, `event_date` в `DATE`, `amount` в `DOUBLE`. Строки с NULL в обязательных полях и с неположительной суммой удаляются. Добавляются `year` из даты и `amount_with_fee = round(amount * 1.05, 2)`.

Результат записывается в `hdfs://team-29-nn:9000/user/team/hw5/output/transactions` как Parquet с партициями по `year`. Повторный запуск перезаписывает результат и использует существующую external table:

```text
id INT
user_name STRING
event_date DATE
category STRING
amount DOUBLE
amount_with_fee DOUBLE
PARTITIONED BY (year INT)
```

## Проверка

После завершения DAG выполнить:

```bash
bash scripts/check.sh
```

Автоматически проверяются:

- версии Airflow и Spark, доступность HDFS и три ожидаемых NodeManager;
- scheduler, webserver на `127.0.0.1:8080`, DAG и отсутствие ошибок импорта DAG;
- четыре задачи, успешный запуск DAG из `last_hw5_run_id` и успешное состояние всех его задач;
- последнее YARN-приложение `hw5-transform` пользователя `team`, его состояния `FINISHED` и `SUCCEEDED`;
- исходный файл и результат в HDFS, `_SUCCESS` и три физических каталога партиций;
- HiveServer2, таблица `hw5.transactions` и ровно три партиции в Hive;
- чтение через Beeline: две строки, семь полей и правильный год в каждой партиции.

Вывод команд остается в терминале. При ошибке `check.sh` завершается с ненулевым кодом.

## Airflow UI

Webserver слушает только `127.0.0.1:8080` на edge. На локальном компьютере открыть SSH-туннель:

```bash
ssh -N -L 8080:127.0.0.1:8080 team@2.59.82.111
```

Затем открыть [http://localhost:8080](http://localhost:8080). Пользователь: `admin`.

Пароль можно посмотреть в отдельной SSH-сессии на edge:

```bash
cat ~/.airflow_hw5_admin_password
```

В интерфейсе видны DAG `hw5_etl`, четыре задачи, состояние запуска DAG, состояния отдельных задач и их логи.

## Результат проверки

Скрипты проверены на кластере команды 29.

- Apache Airflow 2.10.5 запускает DAG `hw5_etl`;
- DAG завершается со статусом `success`;
- все четыре задачи DAG завершаются успешно;
- Spark-приложение `hw5-transform` выполняется под управлением YARN и завершается `SUCCEEDED`;
- результат сохраняется в HDFS в партиции `year=2024`, `year=2025`, `year=2026`;
- Hive видит external table `hw5.transactions` и все три партиции;
- данные читаются через Beeline.
