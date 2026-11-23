"""Fold raw change events into the mirror tables.  python -m botchat_lake.transform [--full]

The mirror holds one row per source key, as it is now. Deletes are kept as rows with
__deleted = true, so a late or replayed event can never bring a deleted row back.
"""

import argparse

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import LongType, StringType, StructField, StructType

from .session import lake_session
from .tables import MIRROR_DB, SOURCES, Source

# Fields Debezium's ExtractNewRecordState adds (add.fields=op,lsn,source.ts_ms, plus
# __deleted from delete.tombstone.handling.mode=rewrite).
META = [
    StructField("__op", StringType()),
    StructField("__lsn", LongType()),
    StructField("__source_ts_ms", LongType()),
    StructField("__deleted", StringType()),
]
META_COLUMNS = [f.name for f in META]


def parse(raw: DataFrame, source: Source) -> DataFrame:
    """Raw JSON records -> typed columns. Unknown JSON fields are ignored."""
    schema = StructType(list(source.fields.fields) + META)
    df = (
        raw.where(F.col("value").isNotNull())  # tombstones carry no row
        .select("partition", "offset", F.from_json("value", schema).alias("r"))
        .select("partition", "offset", "r.*")
        .withColumn("__lsn", F.coalesce("__lsn", F.lit(-1)))
        .withColumn("__deleted", F.lower(F.coalesce("__deleted", F.lit("false"))) == "true")
    )
    for column in source.millis:
        df = df.withColumn(column, F.timestamp_millis(column))
    for column in source.iso:
        df = df.withColumn(column, F.to_timestamp(column))
    return df


def latest(changes: DataFrame, key: str) -> DataFrame:
    """The newest change per key: highest LSN, then the later Kafka record."""
    newest_first = Window.partitionBy(key).orderBy(F.desc("__lsn"), F.desc("partition"), F.desc("offset"))
    return (
        changes.withColumn("_n", F.row_number().over(newest_first))
        .where("_n = 1")
        .drop("_n", "partition", "offset")
    )


def merge_sql(source: Source, view: str) -> str:
    """Upsert newer versions only, so running twice (or out of order) changes nothing."""
    cols = source.columns + META_COLUMNS
    sets = ", ".join(f"t.{c} = s.{c}" for c in cols)
    return (
        f"MERGE INTO {source.mirror} t USING {view} s ON t.{source.key} = s.{source.key} "
        f"WHEN MATCHED AND s.__lsn > t.__lsn THEN UPDATE SET {sets} "
        f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols)}) "
        f"VALUES ({', '.join('s.' + c for c in cols)})"
    )


def transform(spark: SparkSession, lookback_hours: int | None) -> None:
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {MIRROR_DB}")
    for source in SOURCES:
        if not spark.catalog.tableExists(source.raw):
            continue
        raw = spark.table(source.raw)
        if lookback_hours is not None:
            since = F.current_timestamp() - F.make_interval(hours=F.lit(lookback_hours))
            raw = raw.where(F.col("ingested_at") >= since)
        # A temp view over an Iceberg table keeps a reference to that table, which the MERGE
        # can't plan ("No plan for TableReference"). The checkpoint turns it into plain rows.
        updates = latest(parse(raw, source), source.key).localCheckpoint()
        if not spark.catalog.tableExists(source.mirror):
            updates.limit(0).writeTo(source.mirror).using("iceberg").create()
        updates.createOrReplaceTempView("updates")
        spark.sql(merge_sql(source, "updates"))
        print(f"{source.mirror}: merged")


def main() -> None:
    args = argparse.ArgumentParser()
    args.add_argument("--full", action="store_true", help="reprocess every raw record")
    args.add_argument("--lookback-hours", type=int, default=24)
    opts = args.parse_args()
    spark = lake_session("transform")
    try:
        transform(spark, None if opts.full else opts.lookback_hours)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
