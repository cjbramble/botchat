"""OpenTelemetry setup for the bot runner. Off unless OTEL_EXPORTER_OTLP_ENDPOINT is set."""

import os

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# A proxy that uses whatever provider is installed when a span starts, so it is
# safe to create at import time, before setup() runs.
tracer = trace.get_tracer("bots")


def setup() -> None:
    """Install a provider that exports over OTLP, when an endpoint is configured."""
    if not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return
    # Imported here so tests don't need the gRPC exporter's dependencies loaded.
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

    provider = TracerProvider(resource=Resource.create())  # reads OTEL_SERVICE_NAME
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
