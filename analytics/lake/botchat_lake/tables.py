"""What the lake holds: one raw and one mirror table per captured Postgres table."""

from dataclasses import dataclass

from pyspark.sql.types import IntegerType, LongType, StringType, StructField, StructType

RAW_DB = "botchat_raw"  # Kafka records as they arrived, JSON untouched
MIRROR_DB = "botchat_mirror"  # the current state of each source row
DAILY_DB = "botchat_daily"  # small tables for dashboards


@dataclass(frozen=True)
class Source:
    topic: str  # the Kafka topic Debezium writes
    name: str  # table name in the raw and mirror databases
    key: str  # the source table's primary key
    fields: StructType  # the columns as Debezium's JSON carries them
    millis: tuple[str, ...] = ()  # Postgres `timestamp` columns: epoch milliseconds
    iso: tuple[str, ...] = ()  # Postgres `timestamptz` columns: ISO-8601 strings

    @property
    def raw(self) -> str:
        return f"{RAW_DB}.{self.name}"

    @property
    def mirror(self) -> str:
        return f"{MIRROR_DB}.{self.name}"

    @property
    def columns(self) -> list[str]:
        return [f.name for f in self.fields.fields]


def _fields(*pairs) -> StructType:
    return StructType([StructField(name, kind) for name, kind in pairs])


USERS = Source(
    topic="cdc.chat.public.users",
    name="chat_users",
    key="id",
    fields=_fields(
        ("id", LongType()),
        ("nick", StringType()),
        ("kind", StringType()),
        ("level_cache", IntegerType()),
        ("inserted_at", LongType()),
        ("updated_at", LongType()),
    ),
    millis=("inserted_at", "updated_at"),
)

MESSAGES = Source(
    topic="cdc.chat.public.messages",
    name="chat_messages",
    key="id",
    fields=_fields(
        ("id", LongType()),
        ("room", StringType()),
        ("body", StringType()),
        ("user_id", LongType()),
        ("inserted_at", LongType()),
    ),
    millis=("inserted_at",),
)

PLAYERS = Source(
    topic="cdc.game.public.players",
    name="game_players",
    key="player_id",
    fields=_fields(
        ("player_id", StringType()),
        ("xp", LongType()),
        ("updated_at", StringType()),
    ),
    iso=("updated_at",),
)

SOURCES = (USERS, MESSAGES, PLAYERS)
