"""Copy new Kafka records into the raw tables.  python -m botchat_lake.ingest

Each raw table remembers how far it got: its highest offset per partition. Reading
resumes after that, and the append is one atomic Iceberg commit, so a crash either
writes a batch or doesn't, and a rerun never duplicates rows.
"""

import os

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from .session import lake_session
from .tables import RAW_DB, SOURCES

RAW_COLUMNS = (
    "topic STRING, partition INT, offset BIGINT, kafka_ts TIMESTAMP, "
    "key STRING, value STRING, ingested_at TIMESTAMP"
)
ORDER = ["topic", "partition", "offset", "kafka_ts", "key", "value", "ingested_at"]


def new_records(kafka: DataFrame, seen: DataFrame) -> DataFrame:
    """Kafka rows past the highest offset already stored, partition by partition.

    If a partition's newest offset is below what we stored, the topic was recreated
    (Kafka's data was lost) and its offsets started again at 0: take all of it. The
    duplicates that brings are harmless, because the mirror keeps the highest LSN.
    """
    rows = kafka.select(
        "topic",
        "partition",
        "offset",
        F.col("timestamp").alias("kafka_ts"),
        F.col("key").cast("string").alias("key"),
        F.col("value").cast("string").alias("value"),
    )
    stored = seen.groupBy("partition").agg(F.max("offset").alias("seen"))
    newest = rows.groupBy("partition").agg(F.max("offset").alias("newest"))
    seen_, newest_, offset = F.col("seen"), F.col("newest"), F.col("offset")
    return (
        rows.join(stored, "partition", "left")
        .join(newest, "partition")
        .where(seen_.isNull() | (offset > seen_) | (newest_ < seen_))
        .withColumn("ingested_at", F.current_timestamp())
        .select(*ORDER)
    )


def ingest(spark: SparkSession, bootstrap: str) -> None:
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {RAW_DB}")
    for source in SOURCES:
        spark.sql(
            f"CREATE TABLE IF NOT EXISTS {source.raw} ({RAW_COLUMNS}) "
            "USING iceberg PARTITIONED BY (days(ingested_at))"
        )
        kafka = (
            spark.read.format("kafka")
            .option("kafka.bootstrap.servers", bootstrap)
            .option("subscribe", source.topic)
            .option("startingOffsets", "earliest")
            .load()
        )
        rows = new_records(kafka, spark.table(source.raw).select("partition", "offset")).cache()
        count = rows.count()
        if count:
            rows.writeTo(source.raw).append()
        print(f"{source.raw}: +{count} records")
        rows.unpersist()


def main() -> None:
    spark = lake_session("ingest")
    try:
        ingest(spark, os.environ["KAFKA_BOOTSTRAP"])
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
