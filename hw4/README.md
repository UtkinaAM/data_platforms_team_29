# ДЗ4. Введение в платформы данных

Скрипты устанавливают Apache Spark на edge, загружают CSV в HDFS и запускают обработку через существующий YARN. Spark сохраняет результат в Parquet с партициями по году. Таблица создается через HiveServer2, данные читаются стандартным Hive-клиентом Beeline.

## Участники

| ФИО | Telegram | GitHub |
| --- | --- | --- |
| Соленникова София Сергеевна | @an_soc | [poskrebish](https://github.com/poskrebish) |
| Маликова Полина Михайловна | @pomalkv | [pmmalikova](https://github.com/pmmalikova) |
| Пушкарева Анастасия Эдуардовна | @nonetrait | [nonetrait](https://github.com/nonetrait) |
| Уткина Анастасия Михайловна | @aytsantu | [UtkinaAM](https://github.com/UtkinaAM) |

## Архитектура

Spark устанавливается только на `team-29-en`. `spark-submit --master yarn --deploy-mode client` запускает driver на edge, а executors выделяет YARN на существующих NodeManager: `team-29-en`, `team-29-00` и `team-29-01`. Отдельные Spark Master и Worker не используются.

Путь данных:

```text
CSV -> HDFS input -> Spark через YARN -> Parquet с партициями year
    -> Hive external table -> Beeline
```

Spark читает и записывает данные в существующий HDFS. External table создается через HiveServer2 `team-29-en:5433`. Spark напрямую к Hive Metastore не подключается, Hive support в Spark не включается.

## Среда

- Ubuntu 24.04.5 LTS;
- Hadoop 3.4.2;
- OpenJDK 11;
- Apache Spark 3.5.3, сборка `spark-3.5.3-bin-hadoop3`;
- Apache Hive 4.0.0-alpha-2;
- пользователь `team`.

| Компонент | Путь |
| --- | --- |
| Hadoop | `/home/team/hadoop-hw1` |
| Spark | `/home/team/spark-hw4` |
| Hive | `/home/team/hive-hw3` |

Используются работающие HDFS, YARN и Hive из предыдущих ДЗ.

## Структура проекта

```text
hw4/
├── README.md
└── scripts/
    ├── deploy.sh
    ├── load-data.sh
    ├── run.sh
    ├── spark_job.py
    └── check.sh
```

- `deploy.sh`: проверка окружения и установка Spark с проверкой SHA-512.
- `load-data.sh`: создание временного CSV и загрузка в HDFS.
- `run.sh`: запуск Spark через YARN и создание таблицы Hive.
- `spark_job.py`: преобразование данных и запись Parquet.
- `check.sh`: проверка YARN, HDFS и чтения данных через Beeline.

## Развертывание

Команды выполняются на `team-29-en` от пользователя `team`. HDFS, YARN и Hive должны быть запущены. На edge нужен Python 3 для PySpark.

```bash
ssh team@2.59.82.111
```

Обновление репозитория и установка:

```bash
cd ~/data_platforms_team_29
git pull origin main
cd hw4
bash scripts/deploy.sh
```

`deploy.sh` проверяет Java, Hadoop, HDFS и YARN. Если Spark еще не установлен, скрипт скачивает архив и SHA-512 с Apache archive, проверяет контрольную сумму и распаковывает Spark. При повторном запуске используется существующая установка.

`HADOOP_CONF_DIR` и `YARN_CONF_DIR` указывают на `/home/team/hadoop-hw1/etc/hadoop`.

## Загрузка исходных данных

```bash
bash scripts/load-data.sh
```

Скрипт создает CSV из шести строк и загружает его в `/user/team/hw4/input/transactions.csv`. В нем есть `id`, `user_name`, `event_date`, `category` и `amount`, по две записи за 2024, 2025 и 2026 годы. Повторный запуск пересоздает только HDFS-каталог `/user/team/hw4/input`.

## Запуск Spark

```bash
bash scripts/run.sh
```

Приложение `hw4-transform` запускается через YARN в режиме `client`. Для driver и каждого из двух executors задано по `512m` памяти, для executor используется один core. Эти параметры учитывают лимит NodeManager в `1024 MB`. Driver доступен контейнерам по внутреннему IP edge `10.29.0.10`.

Spark читает CSV как строки и явно преобразует `id` в `INT`, `event_date` в `DATE`, `amount` в `DOUBLE`. Удаляются строки с NULL в обязательных полях и с неположительной суммой. Добавляются `year` из даты и `amount_with_fee`, равный `round(amount * 1.05, 2)`.

Результат перезаписывается в `hdfs://team-29-nn:9000/user/team/hw4/output/transactions` в формате Parquet с партиционированием по `year`.

После завершения Spark через существующий Beeline создаются база `hw4` и external table `hw4.transactions`:

```text
id INT
user_name STRING
event_date DATE
category STRING
amount DOUBLE
amount_with_fee DOUBLE
PARTITIONED BY (year INT)
```

`MSCK REPAIR TABLE` добавляет партиции в Hive. Затем Beeline показывает партиции и данные каждого года. Повторный запуск обновляет Parquet и использует существующую таблицу.

## Проверка

```bash
bash scripts/check.sh
```

Скрипт проверяет:

- версии Java и Spark, доступность HDFS и три работающих NodeManager;
- HDFS input и output, файл `_SUCCESS` и физические каталоги `year=2024`, `year=2025`, `year=2026`;
- последнее YARN-приложение `hw4-transform` пользователя `team`, его состояние `FINISHED` и Final-State `SUCCEEDED`;
- порт HiveServer2 `5433`, таблицу `hw4.transactions` и ровно три партиции в Hive;
- чтение каждой партиции стандартным Hive-клиентом Beeline: две строки, семь полей и нужный год.

Вывод команд остается в терминале. При ошибке `check.sh` завершается с ненулевым кодом.
