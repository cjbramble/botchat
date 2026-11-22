package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
)

var tracer = otel.Tracer("github.com/cjbramble/botchat/lambdas/announcer")

// LevelUp is the part of the player.leveled_up event this function reads.
type LevelUp struct {
	Type     string `json:"type"`
	PlayerID string `json:"player_id"`
	NewLevel int    `json:"new_level"`
}

// Notice is what chat's NoticeConsumer expects on the chat-notices queue.
type Notice struct {
	Room      string `json:"room"`
	Text      string `json:"text"`
	DedupeKey string `json:"dedupe_key"`
}

// Sender is the slice of the SQS client this function uses.
type Sender interface {
	SendMessage(ctx context.Context, in *sqs.SendMessageInput, opts ...func(*sqs.Options)) (*sqs.SendMessageOutput, error)
}

// Handler turns level-up records into notices.
type Handler struct {
	SQS      Sender
	QueueURL string
}

// Handle processes one batch. Only records whose notice couldn't be sent are
// reported as failed, so only they are retried.
func (h *Handler) Handle(ctx context.Context, ev events.SQSEvent) (events.SQSEventResponse, error) {
	var failed []events.SQSBatchItemFailure
	for _, rec := range ev.Records {
		if err := h.handleRecord(ctx, rec); err != nil {
			slog.Error("send notice", "id", rec.MessageId, "err", err)
			failed = append(failed, events.SQSBatchItemFailure{ItemIdentifier: rec.MessageId})
		}
	}
	return events.SQSEventResponse{BatchItemFailures: failed}, nil
}

// handleRecord returns an error only when retrying could help. Its span
// continues the trace in the record's attributes, and the notice carries it on.
func (h *Handler) handleRecord(ctx context.Context, rec events.SQSMessage) error {
	ctx = otel.GetTextMapPropagator().Extract(ctx, attributeCarrier(rec.MessageAttributes))
	ctx, span := tracer.Start(ctx, "announce level-up")
	defer span.End()

	var e LevelUp
	if err := json.Unmarshal([]byte(rec.Body), &e); err != nil || e.PlayerID == "" || e.NewLevel < 1 {
		// Retrying malformed JSON won't help: log it and move on.
		slog.Warn("skipping malformed record", "id", rec.MessageId, "err", err)
		return nil
	}
	span.SetAttributes(attribute.String("player.id", e.PlayerID), attribute.Int("level.new", e.NewLevel))

	body, err := json.Marshal(Notice{
		Room:      "games",
		Text:      fmt.Sprintf("*** %s has reached level %d!", e.PlayerID, e.NewLevel),
		DedupeKey: fmt.Sprintf("levelup:%s:%d", e.PlayerID, e.NewLevel),
	})
	if err != nil {
		slog.Error("marshal notice", "id", rec.MessageId, "err", err)
		return nil
	}

	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	attrs := map[string]sqstypes.MessageAttributeValue{}
	for k, v := range carrier {
		attrs[k] = sqstypes.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(v)}
	}

	in := &sqs.SendMessageInput{QueueUrl: aws.String(h.QueueURL), MessageBody: aws.String(string(body))}
	if len(attrs) > 0 {
		in.MessageAttributes = attrs
	}
	_, err = h.SQS.SendMessage(ctx, in)
	return err
}

// attributeCarrier lets the propagator read SQS message attributes.
func attributeCarrier(attrs map[string]events.SQSMessageAttribute) propagation.MapCarrier {
	c := propagation.MapCarrier{}
	for k, v := range attrs {
		if v.StringValue != nil {
			c[k] = *v.StringValue
		}
	}
	return c
}
