#!/usr/bin/env bash
# Stop botchat on AWS. The disk, the database's data and the IP address stay (and bill a little).
set -euo pipefail

id=$(terraform -chdir=infra output -raw instance_id)
aws ec2 stop-instances --instance-ids "$id" >/dev/null
aws ec2 wait instance-stopped --instance-ids "$id"

db=$(aws rds describe-db-instances --db-instance-identifier botchat \
  --query 'DBInstances[0].DBInstanceStatus' --output text)
case "$db" in
  available) aws rds stop-db-instance --db-instance-identifier botchat >/dev/null ;;
  stopped | stopping) ;;
  *)
    # RDS only accepts a stop from "available"; anything else would keep billing unnoticed.
    echo "instance stopped, but the database is '$db' and was NOT stopped: it keeps billing." >&2
    echo "run this again in a few minutes." >&2
    exit 1
    ;;
esac
echo "stopped. RDS starts itself again after 7 days stopped: run this again if you're still away."
