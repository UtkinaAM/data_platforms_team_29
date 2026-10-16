import sys

from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import DoubleType, IntegerType


input_path, output_path = sys.argv[1:]
if not all(path.startswith("hdfs://") for path in (input_path, output_path)):
    raise ValueError("Expected HDFS input and output paths")

spark = (
    SparkSession.builder.appName("hw4-transform")
    .config("spark.sql.catalogImplementation", "in-memory")
    .config("spark.sql.ansi.enabled", "false")
    .getOrCreate()
)
try:
    if spark.sparkContext.master != "yarn":
        raise ValueError("Expected YARN master")

    source = (
        spark.read.option("header", "true")
        .option("mode", "FAILFAST")
        .schema("id STRING, user_name STRING, event_date STRING, category STRING, amount STRING")
        .csv(input_path)
    )
    transformed = (
        source.withColumn("id", F.col("id").cast(IntegerType()))
        .withColumn("event_date", F.to_date("event_date", "yyyy-MM-dd"))
        .withColumn("amount", F.col("amount").cast(DoubleType()))
        .dropna(subset=["id", "user_name", "event_date", "category", "amount"])
        .filter(F.col("amount") > 0)
        .withColumn("year", F.year("event_date"))
        .withColumn("amount_with_fee", F.round(F.col("amount") * 1.05, 2))
        .select("id", "user_name", "event_date", "category", "amount", "amount_with_fee", "year")
    )
    transformed.write.mode("overwrite").partitionBy("year").parquet(output_path)
finally:
    spark.stop()
