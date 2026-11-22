defmodule Chat.Tracing do
  @moduledoc "Helpers for continuing traces that arrive from outside this service."
  require OpenTelemetry.Tracer, as: Tracer

  @headers ["traceparent", "tracestate"]

  @doc """
  Runs `fun` inside a span named `name`, parented to the trace in the SQS
  message's `traceparent` attribute when there is one.
  """
  def with_message_span(name, %Broadway.Message{metadata: metadata}, fun) do
    with_remote_span(name, message_headers(metadata), fun)
  end

  @doc """
  Runs `fun` inside a span named `name`, parented to the trace in `headers`
  (a map or list of `traceparent`/`tracestate` pairs) when there is one.
  """
  def with_remote_span(name, headers, fun) do
    # Starts from an empty context and restores the old one afterwards: these
    # processes are long-lived, and one message's trace must not leak into the next.
    ctx = :otel_propagator_text_map.extract_to(:otel_ctx.new(), clean(headers))
    token = :otel_ctx.attach(ctx)

    try do
      Tracer.with_span(name, do: fun.())
    after
      :otel_ctx.detach(token)
    end
  end

  @doc "The current trace as `traceparent`/`tracestate` pairs, for an outgoing call."
  def headers, do: :otel_propagator_text_map.inject([])

  defp message_headers(%{message_attributes: attrs}) when is_map(attrs) do
    for {key, %{value: value}} <- attrs, do: {key, value}
  end

  defp message_headers(_metadata), do: []

  # Headers come from other services, so anything unexpected is dropped.
  defp clean(headers) when is_map(headers) or is_list(headers) do
    for {key, value} <- headers, key in @headers, is_binary(value), do: {key, value}
  end

  defp clean(_headers), do: []
end
