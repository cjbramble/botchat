"""Small daily tables for dashboards.  python -m botchat_lake.daily --days 2026-11-18,2026-11-19

Each run replaces whole days (overwritePartitions), so rerunning a day gives the same rows.
"""

import argparse
import datetime as dt

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F

from .session import lake_session
from .tables import DAILY_DB, MESSAGES, PLAYERS, USERS


def messages_by_bot(messages: DataFrame, users: DataFrame, days: list[dt.date]) -> DataFrame:
    """Messages per day, room and author."""
    authors = users.select(F.col("id").alias("user_id"), "nick", "kind")
    return (
        messages.where(~F.col("__deleted"))
        .withColumn("day", F.to_date("inserted_at"))
        .where(F.col("day").isin(days))
        .join(authors, "user_id", "left")
        .groupBy("day", "room", "nick", "kind")
        .agg(F.count("*").alias("messages"))
    )


def xp_leaderboard(players: DataFrame, day: dt.date) -> DataFrame:
    """Every player's XP as of this run, ranked, filed under `day`."""
    by_xp = Window.orderBy(F.desc("xp"), F.asc("player_id"))
    return (
        players.where(~F.col("__deleted"))
        .select(F.lit(day).alias("day"), "player_id", "xp")
        .withColumn("rank", F.row_number().over(by_xp))
    )


def write_days(df: DataFrame, table: str) -> None:
    spark = df.sparkSession
    if not spark.catalog.tableExists(table):
        df.limit(0).writeTo(table).using("iceberg").partitionedBy(F.col("day")).create()
    df.writeTo(table).overwritePartitions()


def daily(spark: SparkSession, days: list[dt.date]) -> None:
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {DAILY_DB}")
    if spark.catalog.tableExists(MESSAGES.mirror) and spark.catalog.tableExists(USERS.mirror):
        counts = messages_by_bot(spark.table(MESSAGES.mirror), spark.table(USERS.mirror), days)
        write_days(counts, f"{DAILY_DB}.messages_by_bot")
    if spark.catalog.tableExists(PLAYERS.mirror):
        write_days(xp_leaderboard(spark.table(PLAYERS.mirror), max(days)), f"{DAILY_DB}.xp_leaderboard")


def main() -> None:
    args = argparse.ArgumentParser()
    args.add_argument("--days", required=True, help="comma-separated ISO dates")
    days = [dt.date.fromisoformat(d) for d in args.parse_args().days.split(",")]
    spark = lake_session("daily")
    try:
        daily(spark, days)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
