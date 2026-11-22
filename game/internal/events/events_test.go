package events

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
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

func TestAddTraceContext(t *testing.T) {
	prev := otel.GetTextMapPropagator()
	otel.SetTextMapPropagator(propagation.TraceContext{})
	t.Cleanup(func() { otel.SetTextMapPropagator(prev) })

	traced := trace.ContextWithSpanContext(context.Background(), trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    trace.TraceID{0x0a, 0xf7, 0x65, 0x19, 0x16, 0xcd, 0x43, 0xdd, 0x84, 0x48, 0xeb, 0x21, 0x1c, 0x80, 0x31, 0x9c},
		SpanID:     trace.SpanID{0xb7, 0xad, 0x6b, 0x71, 0x69, 0x20, 0x33, 0x31},
		TraceFlags: trace.FlagsSampled,
	}))

	cases := []struct {
		name string
		ctx  context.Context
		want string // traceparent; "" means the attribute is absent
	}{
		{"a traced context adds traceparent", traced, "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
		{"an untraced context adds nothing", context.Background(), ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			in, err := publishInput("arn:aws:sns:us-east-1:000000000000:game-events", NewLevelUp("pim", 1, 2))
			if err != nil {
				t.Fatal(err)
			}

			addTraceContext(tc.ctx, in)

			attr, ok := in.MessageAttributes["traceparent"]
			if ok != (tc.want != "") || aws.ToString(attr.StringValue) != tc.want {
				t.Errorf("traceparent = %q (present: %v), want %q", aws.ToString(attr.StringValue), ok, tc.want)
			}
			if ok && aws.ToString(attr.DataType) != "String" {
				t.Errorf("traceparent data type = %q, want String", aws.ToString(attr.DataType))
			}
			if _, ok := in.MessageAttributes["type"]; !ok {
				t.Error("the type attribute is gone")
			}
		})
	}
}
