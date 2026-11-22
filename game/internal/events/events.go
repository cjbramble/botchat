// Package events defines the events the game publishes and how they're sent.
package events

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// LevelUp is version 1 of player.leveled_up (see proto/events.md).
type LevelUp struct {
	EventID    string    `json:"event_id"`
	Type       string    `json:"type"`
	Version    int       `json:"version"`
	OccurredAt time.Time `json:"occurred_at"`
	PlayerID   string    `json:"player_id"`
	OldLevel   int       `json:"old_level"`
	NewLevel   int       `json:"new_level"`
}

// NewLevelUp fills in the ID, type, version and time.
func NewLevelUp(player string, oldLevel, newLevel int) LevelUp {
	return LevelUp{EventID: uuid.NewString(), Type: "player.leveled_up", Version: 1,
		OccurredAt: time.Now().UTC(), PlayerID: player, OldLevel: oldLevel, NewLevel: newLevel}
}

// Publisher sends events somewhere.
type Publisher interface {
	Publish(ctx context.Context, e LevelUp) error
}

// LogPublisher logs events instead of sending them: for local dev without AWS.
type LogPublisher struct{}

// Publish logs the event and never fails.
func (LogPublisher) Publish(_ context.Context, e LevelUp) error {
	slog.Info("event", "type", e.Type, "player", e.PlayerID, "level", e.NewLevel)
	return nil
}

// SNSPublisher sends events to a real topic. The "type" message attribute
// lets subscriptions filter without reading the body; "traceparent" carries
// the trace to whoever reads the event.
type SNSPublisher struct {
	Client   *sns.Client
	TopicARN string
}

// Publish sends the event as JSON to the topic.
func (p SNSPublisher) Publish(ctx context.Context, e LevelUp) error {
	in, err := publishInput(p.TopicARN, e)
	if err != nil {
		return err
	}
	addTraceContext(ctx, in)
	if _, err := p.Client.Publish(ctx, in); err != nil {
		return fmt.Errorf("publish %s: %w", e.Type, err)
	}
	return nil
}

// addTraceContext copies the trace in ctx into the request's message
// attributes ("traceparent", and "tracestate" when there is one).
func addTraceContext(ctx context.Context, in *sns.PublishInput) {
	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	for k, v := range carrier {
		in.MessageAttributes[k] = types.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(v)}
	}
}

// publishInput builds the SNS request for an event.
func publishInput(topicARN string, e LevelUp) (*sns.PublishInput, error) {
	body, err := json.Marshal(e)
	if err != nil {
		return nil, fmt.Errorf("marshal %s: %w", e.Type, err)
	}
	return &sns.PublishInput{
		TopicArn: aws.String(topicARN),
		Message:  aws.String(string(body)),
		MessageAttributes: map[string]types.MessageAttributeValue{
			"type": {DataType: aws.String("String"), StringValue: aws.String(e.Type)},
		},
	}, nil
}
