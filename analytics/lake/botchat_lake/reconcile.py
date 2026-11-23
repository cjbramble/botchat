"""Check the lake against Postgres.  python -m botchat_lake.reconcile

Rows older than the cutoff have had time to reach the lake, so their counts must match
exactly. Exits non-zero on any difference, which fails the Airflow task.
"""

import os
import sys

import psycopg
from pyspark.sql import SparkSession

from .session import lake_session
from .tables import MESSAGES, USERS

CHECKS = {  # source table -> mirror table; both have inserted_at
    "users": USERS.mirror,
    "messages": MESSAGES.mirror,
}
CUTOFF = "date_trunc('hour', now() AT TIME ZONE 'UTC') - interval '1 hour'"


def mismatches(postgres: dict[str, int], lake: dict[str, int]) -> list[str]:
    return [
        f"{table}: postgres {postgres[table]}, lake {lake.get(table)}"
        for table in sorted(postgres)
        if postgres[table] != lake.get(table)
    ]


def postgres_counts(url: str) -> tuple[dict[str, int], str]:
    with psycopg.connect(url) as conn:
        cutoff = conn.execute(f"SELECT ({CUTOFF})::text").fetchone()[0]
        counts = {
            table: conn.execute(f"SELECT count(*) FROM {table} WHERE inserted_at < %s", (cutoff,)).fetchone()[
                0
            ]
            for table in CHECKS
        }
    return counts, cutoff


def lake_counts(spark: SparkSession, cutoff: str) -> dict[str, int]:
    return {
        table: spark.sql(
            f"SELECT count(*) FROM {mirror} WHERE NOT __deleted AND inserted_at < TIMESTAMP '{cutoff}'"
        ).first()[0]
        for table, mirror in CHECKS.items()
        if spark.catalog.tableExists(mirror)
    }


def main() -> None:
    postgres, cutoff = postgres_counts(os.environ["RECONCILE_DB_URL"])
    spark = lake_session("reconcile")
    try:
        lake = lake_counts(spark, cutoff)
    finally:
        spark.stop()
    problems = mismatches(postgres, lake)
    for line in problems:
        print("MISMATCH", line)
    if problems:
        sys.exit(1)
    print(f"reconciled {', '.join(CHECKS)} up to {cutoff}")


if __name__ == "__main__":
    main()
