import os
import sys
import time

import pytest
from pyspark.sql import SparkSession


@pytest.fixture(scope="session")
def spark():
    """Plain local Spark: enough for the pure functions, no Iceberg or Kafka jars needed."""
    os.environ.setdefault("PYSPARK_PYTHON", sys.executable)  # workers use this venv's Python
    # PySpark turns timestamps into Python datetimes in the machine's time zone, not the
    # session's, so pin the process (and the JVM it starts) to UTC like CI and the image.
    os.environ["TZ"] = "UTC"
    time.tzset()
    session = (
        SparkSession.builder.master("local[1]")
        .appName("tests")
        .config("spark.sql.session.timeZone", "UTC")
        .config("spark.ui.enabled", "false")
        .config("spark.sql.shuffle.partitions", "1")
        .getOrCreate()
    )
    yield session
    session.stop()
