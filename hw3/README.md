# ДЗ3. Введение в платформы данных

Скрипты разворачивают Apache Hive поверх существующих HDFS и YARN. Используется отдельный Hive Metastore с метаданными во внешнем PostgreSQL. Клиенты подключаются через HiveServer2, а тестовые данные загружаются в партиционированную таблицу.

## Участники

| ФИО | Telegram | GitHub |
| --- | --- | --- |
| Соленникова София Сергеевна | @an_soc | [poskrebish](https://github.com/poskrebish) |
| Маликова Полина Михайловна | @pomalkv | [pmmalikova](https://github.com/pmmalikova) |
| Пушкарева Анастасия Эдуардовна | @nonetrait | [nonetrait](https://github.com/nonetrait) |
| Уткина Анастасия Михайловна | @aytsantu | [UtkinaAM](https://github.com/UtkinaAM) |

## Архитектура

| Узел | Компонент | Порт |
| --- | --- | --- |
| team-29-en | Hive Metastore | 9083 |
| team-29-en | HiveServer2 | 5433 |
| team-29-nn | PostgreSQL | 5432 |

Embedded metastore не используется: HiveServer2 подключается к отдельному Hive Metastore по Thrift, а метаданные хранятся в PostgreSQL. HDFS и YARN используются из ДЗ1 и ДЗ2.

## Среда

- Ubuntu 24.04.5 LTS;
- Hadoop 3.4.2;
- OpenJDK 11;
- Apache Hive 4.0.0-alpha-2;
- PostgreSQL;
- пользователь `team`.

Hadoop расположен в `/home/team/hadoop-hw1`, Hive устанавливается в `/home/team/hive-hw3`. Для запросов используется движок `mr`.

## Структура проекта

```text
hw3/
├── README.md
└── scripts/
    ├── deploy.sh
    ├── start.sh
    ├── stop.sh
    ├── load-data.sh
    └── check.sh
```

- `deploy.sh`: настройка PostgreSQL, установка Hive и подготовка metastore.
- `start.sh`: запуск Hive Metastore и HiveServer2 с ожиданием портов.
- `stop.sh`: остановка сервисов Hive по PID-файлам.
- `load-data.sh`: загрузка трех партиций с тестовыми данными.
- `check.sh`: проверка сервисов, данных и двух параллельных клиентов.

Конфигурация, SQL и временные данные создаются скриптами во время выполнения.

## Развертывание

Команды выполняются на edge-узле `team-29-en` от пользователя `team`. Перед запуском должны работать HDFS и YARN. Для SSH на `team-29-nn` используется ключ `$HOME/.ssh/team_internal`, а `sudo` должен работать без пароля.

Подключение:

```bash
ssh team@2.59.82.111
```

Обновление репозитория и запуск:

```bash
cd ~/data_platforms_team_29
git pull origin main
cd hw3
bash scripts/deploy.sh
```

`deploy.sh` проверяет существующие HDFS и YARN, настраивает PostgreSQL на `team-29-nn`, устанавливает Hive на edge и инициализирует схему metastore, если база пустая. Затем проверяет схему и запускает Hive Metastore и HiveServer2.

Пароль PostgreSQL создается на edge в `$HOME/.hive_hw3_db_password` с правами `600`. Повторное развертывание использует тот же пароль. Конфигурация Hive с паролем также имеет права `600`.

## Запуск и остановка

На edge из каталога `hw3` выполнить:

```bash
bash scripts/start.sh
```

Уже работающие сервисы повторно не запускаются. Логи и PID-файлы находятся в `/home/team/hive-hw3/logs` и `/home/team/hive-hw3/pids`.

Остановка:

```bash
bash scripts/stop.sh
```

`stop.sh` останавливает только HiveServer2 и Hive Metastore.

## Загрузка данных

После развертывания выполнить:

```bash
bash scripts/load-data.sh
```

Создаются база `hw3` и таблица `hw3.events`, партиционированная по `year`. Схема:

```text
id INT
name STRING
event_date STRING
event_type STRING
PARTITIONED BY (year INT)
```

Скрипт готовит шесть строк и загружает партиции `2024`, `2025` и `2026`, по две записи в каждую. `LOAD DATA INPATH` с `OVERWRITE` обновляет эти партиции при повторном запуске без накопления дубликатов. Затем Beeline показывает партиции и содержимое таблицы.

## Проверка

После загрузки данных выполнить:

```bash
bash scripts/check.sh
```

Скрипт проверяет PostgreSQL, схему metastore, процессы Hive Metastore и HiveServer2, порты `9083` и `5433`, HDFS warehouse и подключение Beeline. Для `hw3.events` проверяются три партиции и две строки в каждой. Также запускаются два независимых Beeline-клиента параллельно и проверяются их результаты.

Вывод команд остается в терминале. При ошибке скрипт завершается с ненулевым кодом.

## Подключение

Ручное подключение с edge:

```bash
/home/team/hive-hw3/bin/beeline -u jdbc:hive2://team-29-en:5433/default -n team
```

Для подключения локального клиента в отдельном терминале открыть SSH tunnel:

```bash
ssh -N -L 5433:127.0.0.1:5433 team@2.59.82.111
```

После этого использовать JDBC-адрес:

```text
jdbc:hive2://localhost:5433/default
```
