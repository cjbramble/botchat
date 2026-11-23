"""Loads the DAG the way Airflow's DAG processor does, without a database.
Skipped where Airflow isn't installed; it runs inside the Airflow image (16.10)."""

from pathlib import Path

import pytest

DagBag = pytest.importorskip("airflow.dag_processing.dagbag").DagBag

DAGS = Path(__file__).resolve().parent.parent / "dags"


@pytest.fixture(scope="module")
def bag():
    return DagBag(dag_folder=str(DAGS))


def test_dags_import_cleanly(bag):
    assert bag.import_errors == {}
    assert set(bag.dags) == {"botchat_lake", "botchat_daily"}


def test_tasks_run_in_order(bag):
    dag = bag.dags["botchat_lake"]
    assert dag.get_task("ingest").downstream_task_ids == {"mirror"}
    assert dag.get_task("mirror").downstream_task_ids == {"daily", "reconcile"}
    assert dag.max_active_runs == 1 and dag.catchup is False


def test_daily_dag_finalizes_yesterday(bag):
    task = bag.dags["botchat_daily"].get_task("daily")
    assert "macros.ds_add(ds, -1)" in task.bash_command
