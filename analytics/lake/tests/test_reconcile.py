from botchat_lake.reconcile import mismatches


def test_equal_counts_are_fine():
    assert mismatches({"users": 43, "messages": 900}, {"users": 43, "messages": 900}) == []


def test_differences_and_missing_tables_are_reported():
    out = mismatches({"users": 43, "messages": 900}, {"users": 42})
    assert out == ["messages: postgres 900, lake None", "users: postgres 43, lake 42"]
