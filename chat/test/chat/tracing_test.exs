defmodule Chat.TracingTest do
  use ExUnit.Case, async: true

  require OpenTelemetry.Tracer, as: Tracer

  alias Chat.Tracing

  @trace_id "0af7651916cd43dd8448eb211c80319c"
  @traceparent "00-#{@trace_id}-b7ad6b7169203331-01"

  defp current_trace_id, do: OpenTelemetry.Span.hex_trace_id(Tracer.current_span_ctx())

  defp message(attributes) do
    %Broadway.Message{data: "{}", acknowledger: nil, metadata: %{message_attributes: attributes}}
  end

  describe "with_remote_span/3" do
    test "continues the trace in the headers and returns the function's result" do
      assert {:done, @trace_id} =
               Tracing.with_remote_span("test", %{"traceparent" => @traceparent}, fn ->
                 {:done, current_trace_id()}
               end)
    end

    test "starts a new trace without headers" do
      for headers <- [nil, %{}, [], "junk", %{"traceparent" => 42}, %{"traceparent" => "junk"}] do
        trace_id = Tracing.with_remote_span("test", headers, &current_trace_id/0)

        assert trace_id =~ ~r/\A[0-9a-f]{32}\z/
        refute trace_id == @trace_id
        refute trace_id == String.duplicate("0", 32)
      end
    end

    test "one message's trace doesn't leak into the next" do
      Tracing.with_remote_span("first", %{"traceparent" => @traceparent}, fn -> :ok end)

      assert Tracer.current_span_ctx() == :undefined
      refute Tracing.with_remote_span("second", nil, &current_trace_id/0) == @trace_id
    end

    test "restores the caller's trace even when the function raises" do
      Tracer.with_span "outer" do
        outer = current_trace_id()

        assert_raise RuntimeError, fn ->
          Tracing.with_remote_span("inner", %{"traceparent" => @traceparent}, fn ->
            raise "boom"
          end)
        end

        assert current_trace_id() == outer
      end
    end
  end

  describe "with_message_span/3" do
    test "continues the trace in the SQS message attributes" do
      attributes = %{
        "traceparent" => %{name: "traceparent", data_type: "String", value: @traceparent},
        "type" => %{name: "type", data_type: "String", value: "player.leveled_up"}
      }

      assert Tracing.with_message_span("test", message(attributes), &current_trace_id/0) ==
               @trace_id
    end

    test "starts a new trace for a message without attributes" do
      for message <- [message(%{}), message(nil), %Broadway.Message{data: "", acknowledger: nil}] do
        refute Tracing.with_message_span("test", message, &current_trace_id/0) == @trace_id
      end
    end
  end

  describe "headers/0" do
    test "carries the current span, and nothing outside one" do
      assert Tracing.headers() == []

      Tracing.with_remote_span("test", %{"traceparent" => @traceparent}, fn ->
        assert [{"traceparent", "00-" <> rest}] = Tracing.headers()
        assert String.starts_with?(rest, @trace_id)
        # The span started here is the parent, not the remote one.
        refute rest =~ "b7ad6b7169203331"
      end)
    end
  end
end
