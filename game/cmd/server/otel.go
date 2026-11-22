package main

import (
	"context"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// setupTracing installs a global tracer provider that exports over OTLP.
// It reads OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_SERVICE_NAME from the
// environment. Without an endpoint, tracing stays off (a no-op provider).
func setupTracing(ctx context.Context) (shutdown func(context.Context) error, err error) {
	// Set even when exporting is off, so trace context still passes through.
	otel.SetTextMapPropagator(propagation.TraceContext{})
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		return func(context.Context) error { return nil }, nil
	}
	exp, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp))
	otel.SetTracerProvider(tp)
	return tp.Shutdown, nil
}
