"""Run one Spark SQL query against the lake and print the result.

Usage: python -m botchat_lake.sql "SELECT * FROM botchat_daily.xp_leaderboard LIMIT 10"
"""

import sys

from .session import lake_session


def main() -> None:
    spark = lake_session("sql")
    try:
        spark.sql(" ".join(sys.argv[1:])).show(50, truncate=False)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
