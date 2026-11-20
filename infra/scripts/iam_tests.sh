#!/usr/bin/env bash
# Usage: ./scripts/iam_tests.sh   (from infra/, after terraform apply)
set -uo pipefail
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TOPIC=$(terraform output -raw game_events_topic_arn)
LEVELS=$(aws sqs get-queue-attributes --queue-url "$(terraform output -raw level_updates_queue_url)" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)
NOTICES=$(aws sqs get-queue-attributes --queue-url "$(terraform output -raw chat_notices_queue_url)" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)
FAILED=0

check() {  # check <id> <want> <got> <action>
  if [[ "$3" == "$2" ]]; then echo "PASS  $1"; else echo "FAIL  $1: $4 -> $3, want $2"; FAILED=1; fi
}

# A role: simulate everything attached to it.
expect_role() {  # expect_role <id> <allowed|implicitDeny> <role-arn> <action> <resource>
  got=$(aws iam simulate-principal-policy --policy-source-arn "$3" --action-names "$4" \
          --resource-arns "$5" --query 'EvaluationResults[0].EvalDecision' --output text)
  check "$1" "$2" "$got" "$4"
}

# A managed policy on its own: fetch its current document and simulate just that.
policy_doc() {
  local arn="arn:aws:iam::$ACCOUNT:policy/$1" version
  version=$(aws iam get-policy --policy-arn "$arn" --query Policy.DefaultVersionId --output text)
  aws iam get-policy-version --policy-arn "$arn" --version-id "$version" \
    --query PolicyVersion.Document --output json
}
expect_policy() {  # expect_policy <id> <allowed|implicitDeny> <policy-json> <action> <resource>
  got=$(aws iam simulate-custom-policy --policy-input-list "$3" --action-names "$4" \
          --resource-arns "$5" --query 'EvaluationResults[0].EvalDecision' --output text)
  check "$1" "$2" "$got" "$4"
}

GAME=$(policy_doc botchat-game-publisher)
CHAT=$(policy_doc botchat-chat-consumer)
LAMBDA="arn:aws:iam::$ACCOUNT:role/botchat-announcer"

expect_policy INFRA-IAM-01 allowed      "$GAME"   sns:Publish        "$TOPIC"
expect_policy INFRA-IAM-02 implicitDeny "$GAME"   sqs:ReceiveMessage "$LEVELS"
expect_policy INFRA-IAM-03 implicitDeny "$GAME"   sns:DeleteTopic    "$TOPIC"
expect_policy INFRA-IAM-04 allowed      "$CHAT"   sqs:ReceiveMessage "$LEVELS"
expect_policy INFRA-IAM-05 allowed      "$CHAT"   sqs:DeleteMessage  "$NOTICES"
expect_policy INFRA-IAM-06 implicitDeny "$CHAT"   sqs:SendMessage    "$NOTICES"
expect_role   INFRA-IAM-07 allowed      "$LAMBDA" sqs:SendMessage    "$NOTICES"
expect_role   INFRA-IAM-08 implicitDeny "$LAMBDA" sqs:SendMessage    "$LEVELS"
expect_role   INFRA-IAM-09 implicitDeny "$LAMBDA" sqs:ReceiveMessage "$LEVELS"
exit $FAILED
