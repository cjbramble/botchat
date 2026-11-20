// Command announcer is an AWS Lambda that turns level-up events into chat notices.
package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

func main() {
	queueURL := os.Getenv("CHAT_NOTICES_QUEUE_URL")
	if queueURL == "" {
		slog.Error("CHAT_NOTICES_QUEUE_URL is required")
		os.Exit(1)
	}
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		slog.Error("aws config", "err", err)
		os.Exit(1)
	}
	h := &Handler{SQS: sqs.NewFromConfig(cfg), QueueURL: queueURL}
	lambda.Start(h.Handle)
}
