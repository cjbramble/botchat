"""One SparkSession for every job, pointed at the local lake or the one on AWS.

LAKE_CATALOG=local  Iceberg tables in a folder (LAKE_WAREHOUSE=file:///lake), for Compose.
LAKE_CATALOG=glue   Iceberg tables in S3 (LAKE_WAREHOUSE=s3://bucket/warehouse), listed in Glue.
"""

import os
from collections.abc import Mapping

import pyspark
from pyspark.sql import SparkSession

ICEBERG = "1.11.0"
PACKAGES = ",".join(
    [
        f"org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:{ICEBERG}",
        f"org.apache.iceberg:iceberg-aws-bundle:{ICEBERG}",
        f"org.apache.spark:spark-sql-kafka-0-10_2.13:{pyspark.__version__}",
    ]
)


def lake_conf(env: Mapping[str, str]) -> dict[str, str]:
    """Spark settings for the catalog named `lake`, from environment variables."""
    catalog = env.get("LAKE_CATALOG", "local")
    conf = {
        "spark.sql.extensions": "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        "spark.sql.catalog.lake": "org.apache.iceberg.spark.SparkCatalog",
        "spark.sql.catalog.lake.warehouse": env["LAKE_WAREHOUSE"],
        "spark.sql.defaultCatalog": "lake",
        "spark.sql.session.timeZone": "UTC",
    }
    if catalog == "local":
        conf["spark.sql.catalog.lake.type"] = "hadoop"
    elif catalog == "glue":
        conf["spark.sql.catalog.lake.catalog-impl"] = "org.apache.iceberg.aws.glue.GlueCatalog"
        conf["spark.sql.catalog.lake.io-impl"] = "org.apache.iceberg.aws.s3.S3FileIO"
    else:
        raise ValueError(f"LAKE_CATALOG must be local or glue, not {catalog!r}")
    return conf


def builder(app: str) -> SparkSession.Builder:
    return (
        SparkSession.builder.appName(app)
        .master(os.environ.get("SPARK_MASTER", "local[2]"))
        .config("spark.jars.packages", PACKAGES)
        .config("spark.driver.memory", os.environ.get("SPARK_DRIVER_MEMORY", "2g"))
        .config("spark.ui.enabled", "false")
    )


def lake_session(app: str) -> SparkSession:
    b = builder(app)
    for key, value in lake_conf(os.environ).items():
        b = b.config(key, value)
    return b.getOrCreate()


if __name__ == "__main__":
    # `python -m botchat_lake.session` downloads the jars once, at image build time.
    builder("warm-cache").getOrCreate().stop()
