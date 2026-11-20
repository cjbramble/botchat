package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type fakeSQS struct {
	sent []string
	fail bool
	// failFor fails only the sends whose body contains it.
	failFor string
}

func (f *fakeSQS) SendMessage(_ context.Context, in *sqs.SendMessageInput, _ ...func(*sqs.Options)) (*sqs.SendMessageOutput, error) {
	if f.fail || (f.failFor != "" && strings.Contains(*in.MessageBody, f.failFor)) {
		return nil, errors.New("boom")
	}
	f.sent = append(f.sent, *in.MessageBody)
	return &sqs.SendMessageOutput{}, nil
}

func batch(bodies ...string) events.SQSEvent {
	var ev events.SQSEvent
	for i, b := range bodies {
		ev.Records = append(ev.Records, events.SQSMessage{MessageId: string(rune('1' + i)), Body: b})
	}
	return ev
}

func TestSendsANoticePerLevelUp(t *testing.T) {
	q := &fakeSQS{}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(),
		batch(`{"type":"player.leveled_up","player_id":"pim","new_level":5}`))
	if err != nil || len(resp.BatchItemFailures) != 0 || len(q.sent) != 1 {
		t.Fatalf("got %d sent, %+v, %v", len(q.sent), resp, err)
	}
	for _, want := range []string{"pim has reached level 5", `"dedupe_key":"levelup:pim:5"`, `"room":"games"`} {
		if !strings.Contains(q.sent[0], want) {
			t.Errorf("notice %s is missing %s", q.sent[0], want)
		}
	}
}

func TestMalformedRecordsAreSkippedNotRetried(t *testing.T) {
	q := &fakeSQS{}
	resp, _ := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(),
		batch(`not json`, `{"player_id":""}`, `{"player_id":"pim","new_level":0}`,
			`{"type":"player.leveled_up","new_level":2}`))
	if len(resp.BatchItemFailures) != 0 || len(q.sent) != 0 {
		t.Fatalf("want nothing sent and nothing retried, got %d sent, %+v", len(q.sent), resp)
	}
}

func TestOnlyFailedSendsAreRetried(t *testing.T) {
	q := &fakeSQS{fail: true}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(),
		batch(`{"player_id":"pim","new_level":5}`, `not json`))
	if err != nil || len(resp.BatchItemFailures) != 1 || resp.BatchItemFailures[0].ItemIdentifier != "1" {
		t.Fatalf("want only record 1 reported, got %+v, %v", resp, err)
	}
}

func TestOneFailedSendOfThreeIsTheOnlyRetry(t *testing.T) {
	q := &fakeSQS{failFor: "zed"}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(),
		batch(`{"player_id":"pim","new_level":5}`, `{"player_id":"zed","new_level":2}`, `{"player_id":"ada","new_level":3}`))
	if err != nil || len(resp.BatchItemFailures) != 1 || resp.BatchItemFailures[0].ItemIdentifier != "2" {
		t.Fatalf("want only record 2 reported, got %+v, %v", resp, err)
	}
	if len(q.sent) != 2 {
		t.Errorf("want the other 2 notices sent, got %d", len(q.sent))
	}
}

func TestEmptyBatchDoesNothing(t *testing.T) {
	q := &fakeSQS{}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(), events.SQSEvent{})
	if err != nil || len(resp.BatchItemFailures) != 0 || len(q.sent) != 0 {
		t.Fatalf("want no sends, no failures, no error, got %d sent, %+v, %v", len(q.sent), resp, err)
	}
}

func TestSampleEventSendsOneNoticeAndRetriesNothing(t *testing.T) {
	raw, err := os.ReadFile("testdata/two-records.json")
	if err != nil {
		t.Fatal(err)
	}
	var ev events.SQSEvent
	if err := json.Unmarshal(raw, &ev); err != nil {
		t.Fatal(err)
	}
	q := &fakeSQS{}
	resp, err := (&Handler{SQS: q, QueueURL: "q"}).Handle(context.Background(), ev)
	if err != nil || len(resp.BatchItemFailures) != 0 || len(q.sent) != 1 {
		t.Fatalf("want 1 sent and nothing retried, got %d sent, %+v, %v", len(q.sent), resp, err)
	}
	if !strings.Contains(q.sent[0], "*** qa_bot has reached level 2!") {
		t.Errorf("unexpected notice %s", q.sent[0])
	}
}
