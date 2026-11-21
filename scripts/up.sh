#!/usr/bin/env bash
# Start botchat on AWS: the database and the instance, in parallel.
set -euo pipefail

id=$(terraform -chdir=infra output -raw instance_id)
db=$(aws rds describe-db-instances --db-instance-identifier botchat \
  --query 'DBInstances[0].DBInstanceStatus' --output text)

if [[ "$db" == "stopping" ]]; then
  # RDS only accepts a start from "stopped"; waiting here would time out with it still down.
  echo "the database is still stopping; nothing was started. Run this again in a few minutes." >&2
  exit 1
fi
if [[ "$db" == "stopped" ]]; then
  aws rds start-db-instance --db-instance-identifier botchat >/dev/null
fi
aws ec2 start-instances --instance-ids "$id" >/dev/null

aws ec2 wait instance-running --instance-ids "$id"
aws rds wait db-instance-available --db-instance-identifier botchat
echo "up. Pods that started before the database restart until it answers (a minute or two)."
echo "for kubectl: ./scripts/tunnel.sh in another terminal"
