package events

import (
	"encoding/json"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
)

func TestLevelUpMatchesTheContract(t *testing.T) {
	body, err := json.Marshal(NewLevelUp("pim", 4, 5))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"type": "player.leveled_up", "version": float64(1),
		"player_id": "pim", "old_level": float64(4), "new_level": float64(5),
	}
	for key, v := range want {
		if got[key] != v {
			t.Errorf("%q = %v, want %v in %s", key, got[key], v, body)
		}
	}
	for _, key := range []string{"event_id", "occurred_at"} {
		if s, ok := got[key].(string); !ok || s == "" {
			t.Errorf("missing %q in %s", key, body)
		}
	}
	if len(got) != 7 {
		t.Errorf("got %d keys, want 7 in %s", len(got), body)
	}
}

func TestPublishInputSetsTheTypeAttribute(t *testing.T) {
	e := NewLevelUp("pim", 1, 2)
	in, err := publishInput("arn:aws:sns:us-east-1:000000000000:game-events", e)
	if err != nil {
		t.Fatal(err)
	}
	attr, ok := in.MessageAttributes["type"]
	if !ok || aws.ToString(attr.DataType) != "String" || aws.ToString(attr.StringValue) != "player.leveled_up" {
		t.Errorf("type attribute = %+v", attr)
	}
	var body LevelUp
	if err := json.Unmarshal([]byte(aws.ToString(in.Message)), &body); err != nil {
		t.Fatal(err)
	}
	if body != e {
		t.Errorf("message = %+v, want %+v", body, e)
	}
}
