"""Two DAGs for botchat's lake. Each task is a separate Spark process.

botchat_lake   every hour: new Kafka records -> raw -> mirror -> today's daily rows,
               then check the lake against Postgres.
botchat_daily  every day: recompute yesterday's daily rows once it's complete. Also the
               DAG to backfill when daily.py changes (one run per day).
"""

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

COMMON = {
    "start_date": pendulum.datetime(2026, 11, 1, tz="UTC"),
    "catchup": False,  # the instance is off at night: don't replay the slots it missed
    "max_active_runs": 1,  # two MERGEs into one table at once would conflict
    "default_args": {"retries": 1, "retry_delay": pendulum.duration(minutes=5)},
    "tags": ["botchat"],
}

with DAG(dag_id="botchat_lake", schedule="@hourly", **COMMON):
    ingest = BashOperator(task_id="ingest", bash_command="python -m botchat_lake.ingest")
    mirror = BashOperator(task_id="mirror", bash_command="python -m botchat_lake.transform")
    today = BashOperator(task_id="daily", bash_command="python -m botchat_lake.daily --days {{ ds }}")
    reconcile = BashOperator(task_id="reconcile", bash_command="python -m botchat_lake.reconcile")

    ingest >> mirror >> [today, reconcile]

with DAG(dag_id="botchat_daily", schedule="30 0 * * *", **COMMON):
    # A run on day D (at 00:30 UTC) finalizes D-1.
    BashOperator(
        task_id="daily",
        bash_command="python -m botchat_lake.daily --days {{ macros.ds_add(ds, -1) }}",
    )
