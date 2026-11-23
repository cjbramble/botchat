import datetime as dt

from botchat_lake.ingest import ORDER, new_records

TS = dt.datetime(2026, 11, 19, 12, 0)


def kafka_rows(spark, offsets_by_partition):
    rows = [
        ("cdc.chat.public.messages", p, o, TS, b"k", b'{"id": 1}')
        for p, offsets in offsets_by_partition.items()
        for o in offsets
    ]
    return spark.createDataFrame(
        rows,
        "topic string, partition int, offset long, timestamp timestamp, key binary, value binary",
    )


def seen(spark, pairs):
    return spark.createDataFrame(pairs, "partition int, offset long")


def test_everything_is_new_when_the_table_is_empty(spark):
    out = new_records(kafka_rows(spark, {0: [0, 1, 2]}), seen(spark, []))
    assert sorted(r.offset for r in out.collect()) == [0, 1, 2]
    assert out.columns == ORDER


def test_resumes_after_the_highest_stored_offset_per_partition(spark):
    kafka = kafka_rows(spark, {0: [0, 1, 2, 3], 1: [0, 1]})
    out = new_records(kafka, seen(spark, [(0, 0), (0, 1), (1, 0)]))
    assert sorted((r.partition, r.offset) for r in out.collect()) == [(0, 2), (0, 3), (1, 1)]


def test_a_new_partition_starts_from_the_beginning(spark):
    out = new_records(kafka_rows(spark, {0: [5], 1: [0]}), seen(spark, [(0, 5)]))
    assert [(r.partition, r.offset) for r in out.collect()] == [(1, 0)]


def test_a_recreated_topic_is_read_again_from_the_start(spark):
    out = new_records(kafka_rows(spark, {0: [0, 1]}), seen(spark, [(0, 500)]))
    assert sorted(r.offset for r in out.collect()) == [0, 1]


def test_key_and_value_become_strings(spark):
    row = new_records(kafka_rows(spark, {0: [0]}), seen(spark, [])).first()
    assert (row.key, row.value) == ("k", '{"id": 1}')
    assert row.ingested_at is not None
