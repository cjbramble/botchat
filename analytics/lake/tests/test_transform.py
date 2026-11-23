import datetime as dt
import json

from botchat_lake.tables import MESSAGES, PLAYERS, USERS
from botchat_lake.transform import latest, merge_sql, parse


def raw(spark, *records):
    """records: (offset, dict or None). None is a Kafka tombstone."""
    rows = [(0, o, None if r is None else json.dumps(r)) for o, r in records]
    return spark.createDataFrame(rows, "partition int, offset long, value string")


def message(id, lsn, op="c", deleted="false", **extra):
    return {
        "id": id,
        "room": "#python",
        "body": "hi",
        "user_id": 7,
        "inserted_at": 1763553600123,
        "__op": op,
        "__lsn": lsn,
        "__source_ts_ms": 1763553600200,
        "__deleted": deleted,
        **extra,
    }


def test_parse_types_columns_and_converts_epoch_millis(spark):
    row = parse(raw(spark, (0, message(1, 100))), MESSAGES).first()
    assert row.id == 1 and row.room == "#python" and row["__lsn"] == 100
    assert row.inserted_at == dt.datetime(2025, 11, 19, 12, 0, 0, 123000)
    assert row["__deleted"] is False


def test_parse_skips_tombstones_and_ignores_unknown_fields(spark):
    rows = parse(raw(spark, (0, None), (1, message(1, 100, note="new column"))), MESSAGES).collect()
    assert len(rows) == 1
    assert "note" not in rows[0].asDict()


def test_parse_reads_deletes_whether_flag_is_string_or_boolean(spark):
    rows = parse(
        raw(
            spark,
            (0, message(1, 5, op="d", deleted="true")),
            (1, message(2, 6, op="d", deleted=True)),
        ),
        MESSAGES,
    ).collect()
    assert [r["__deleted"] for r in rows] == [True, True]


def test_parse_converts_iso_timestamps(spark):
    player = {
        "player_id": "pim",
        "xp": 120,
        "updated_at": "2026-11-19T10:15:30.5Z",
        "__op": "u",
        "__lsn": 9,
        "__source_ts_ms": 1,
        "__deleted": "false",
    }
    row = parse(raw(spark, (0, player)), PLAYERS).first()
    assert row.updated_at == dt.datetime(2026, 11, 19, 10, 15, 30, 500000)


def test_latest_keeps_the_highest_lsn_per_key(spark):
    changes = parse(
        raw(
            spark,
            (0, message(1, 100)),
            (1, message(1, 300, op="u")),
            (2, message(1, 200, op="u")),
            (3, message(2, 150)),
        ),
        MESSAGES,
    )
    out = {r.id: r["__lsn"] for r in latest(changes, "id").collect()}
    assert out == {1: 300, 2: 150}


def test_latest_breaks_lsn_ties_with_the_later_record(spark):
    changes = parse(
        raw(
            spark,
            (0, {**message(1, 100), "body": "first"}),
            (1, {**message(1, 100), "body": "second"}),
        ),
        MESSAGES,
    )
    assert latest(changes, "id").first().body == "second"
    assert "offset" not in latest(changes, "id").columns


def test_merge_only_applies_newer_versions_and_never_hard_deletes():
    sql = merge_sql(USERS, "updates")
    assert "MERGE INTO botchat_mirror.chat_users t USING updates s ON t.id = s.id" in sql
    assert "WHEN MATCHED AND s.__lsn > t.__lsn THEN UPDATE SET" in sql
    assert "t.__deleted = s.__deleted" in sql
    assert "DELETE" not in sql
