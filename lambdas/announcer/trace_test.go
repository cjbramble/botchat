package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// attrSQS records the message attributes of each notice.
type attrSQS struct {
	sent []map[string]sqstypes.MessageAttributeValue
}

func (a *attrSQS) SendMessage(_ context.Context, in *sqs.SendMessageInput, _ ...func(*sqs.Options)) (*sqs.SendMessageOutput, error) {
	a.sent = append(a.sent, in.MessageAttributes)
	return &sqs.SendMessageOutput{}, nil
}

func TestNoticeCarriesEachRecordsTrace(t *testing.T) {
	prev := otel.GetTextMapPropagator()
	otel.SetTextMapPropagator(propagation.TraceContext{})
	t.Cleanup(func() { otel.SetTextMapPropagator(prev) })

	const (
		first  = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
		second = "00-11111111111111111111111111111111-2222222222222222-01"
	)
	record := func(id, traceparent string) events.SQSMessage {
		rec := events.SQSMessage{MessageId: id, Body: `{"type":"player.leveled_up","player_id":"pim","new_level":5}`}
		if traceparent != "" {
			rec.MessageAttributes = map[string]events.SQSMessageAttribute{
				"traceparent": {DataType: "String", StringValue: aws.String(traceparent)},
				"type":        {DataType: "String", StringValue: aws.String("player.leveled_up")},
			}
		}
		return rec
	}

	q := &attrSQS{}
	ev := events.SQSEvent{Records: []events.SQSMessage{record("1", first), record("2", ""), record("3", second)}}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(), ev)
	if err != nil || len(resp.BatchItemFailures) != 0 || len(q.sent) != 3 {
		t.Fatalf("got %d sent, %+v, %v", len(q.sent), resp, err)
	}

	// Without an exporter the function records no span of its own, so the
	// notice names the same parent the record did.
	for i, want := range []string{first, "", second} {
		attr, ok := q.sent[i]["traceparent"]
		if ok != (want != "") || aws.ToString(attr.StringValue) != want {
			t.Errorf("notice %d: traceparent = %q (present: %v), want %q", i+1, aws.ToString(attr.StringValue), ok, want)
		}
		if ok && aws.ToString(attr.DataType) != "String" {
			t.Errorf("notice %d: traceparent data type = %q, want String", i+1, aws.ToString(attr.DataType))
		}
		if _, ok := q.sent[i]["type"]; ok {
			t.Errorf("notice %d: the record's type attribute was copied to the notice", i+1)
		}
	}
}
