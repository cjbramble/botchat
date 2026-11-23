import pytest

from botchat_lake.session import PACKAGES, lake_conf


def test_local_catalog_is_a_folder():
    conf = lake_conf({"LAKE_WAREHOUSE": "file:///lake"})
    assert conf["spark.sql.catalog.lake.type"] == "hadoop"
    assert conf["spark.sql.catalog.lake.warehouse"] == "file:///lake"
    assert conf["spark.sql.defaultCatalog"] == "lake"


def test_glue_catalog_uses_s3_file_io():
    conf = lake_conf({"LAKE_CATALOG": "glue", "LAKE_WAREHOUSE": "s3://b/warehouse"})
    assert conf["spark.sql.catalog.lake.catalog-impl"].endswith("GlueCatalog")
    assert conf["spark.sql.catalog.lake.io-impl"].endswith("S3FileIO")
    assert "spark.sql.catalog.lake.type" not in conf


def test_unknown_catalog_is_refused():
    with pytest.raises(ValueError):
        lake_conf({"LAKE_CATALOG": "hive", "LAKE_WAREHOUSE": "x"})


def test_kafka_package_matches_installed_spark():
    import pyspark

    assert f"spark-sql-kafka-0-10_2.13:{pyspark.__version__}" in PACKAGES
