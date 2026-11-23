import datetime as dt

from botchat_lake.daily import messages_by_bot, xp_leaderboard

D1, D2 = dt.date(2026, 11, 18), dt.date(2026, 11, 19)


def test_messages_by_bot_counts_per_day_room_and_author(spark):
    messages = spark.createDataFrame(
        [
            (1, "#python", 7, dt.datetime(2026, 11, 18, 23, 59), False),
            (2, "#python", 7, dt.datetime(2026, 11, 19, 0, 1), False),
            (3, "#python", 7, dt.datetime(2026, 11, 19, 8, 0), False),
            (4, "#games", 8, dt.datetime(2026, 11, 19, 9, 0), True),  # deleted
            (5, "#games", 8, dt.datetime(2026, 11, 17, 9, 0), False),  # outside the days
        ],
        "id long, room string, user_id long, inserted_at timestamp, __deleted boolean",
    )
    users = spark.createDataFrame([(7, "pim", "bot"), (8, "ada", "bot")], "id long, nick string, kind string")
    out = {(r.day, r.room, r.nick): r.messages for r in messages_by_bot(messages, users, [D1, D2]).collect()}
    assert out == {(D1, "#python", "pim"): 1, (D2, "#python", "pim"): 2}


def test_xp_leaderboard_ranks_by_xp_then_name(spark):
    players = spark.createDataFrame(
        [("pim", 50, False), ("ada", 90, False), ("bob", 50, False), ("old", 999, True)],
        "player_id string, xp long, __deleted boolean",
    )
    rows = xp_leaderboard(players, D2).orderBy("rank").collect()
    assert [(r.player_id, r.rank) for r in rows] == [("ada", 1), ("bob", 2), ("pim", 3)]
    assert {r.day for r in rows} == {D2}
