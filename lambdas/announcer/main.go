// Command announcer is an AWS Lambda that turns level-up events into chat notices.
package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func main() {
	queueURL := os.Getenv("CHAT_NOTICES_QUEUE_URL")
	if queueURL == "" {
		slog.Error("CHAT_NOTICES_QUEUE_URL is required")
		os.Exit(1)
	}
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("aws config", "err", err)
		os.Exit(1)
	}

	// The propagator is set even without an exporter, so traceparent still
	// passes from the incoming record to the outgoing notice.
	otel.SetTextMapPropagator(propagation.TraceContext{})
	flush := func(context.Context) error { return nil }
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "" {
		exp, err := otlptracegrpc.New(ctx)
		if err != nil {
			slog.Error("tracing", "err", err)
			os.Exit(1)
		}
		tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp))
		otel.SetTracerProvider(tp)
		flush = tp.ForceFlush
	}

	h := &Handler{SQS: sqs.NewFromConfig(cfg), QueueURL: queueURL}
	lambda.Start(func(ctx context.Context, ev events.SQSEvent) (events.SQSEventResponse, error) {
		resp, err := h.Handle(ctx, ev)
		// AWS may freeze the process right after the handler returns.
		if ferr := flush(ctx); ferr != nil {
			slog.Warn("flush traces", "err", ferr)
		}
		return resp, err
	})
}
