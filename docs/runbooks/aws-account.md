# AWS account runbook

Procedures and names for the AWS setup behind botchat. No secrets or real IDs live here.

## Accounts

The setup is an AWS organization of three accounts, created through AWS Settings
(<https://settings.aws.com/projects>) with advanced features activated.

| Account | ID | Use |
|---|---|---|
| Project account `<project-name>` | `<project-account-id>` | Every botchat resource lives here. |
| Management account | `<management-account-id>` | Organization, billing, service control policies. No workloads. |
| Identity Delegated Admin | `<identity-account-id>` | AWS-created; runs sign-in and user management. No workloads. Do not deregister it. |

## Access

- Daily login: AWS Builder ID `<you>`, MFA on. It assumes `AccountFullAccessRole` in each account.
- There are no IAM users and no IAM Identity Center users; `aws sso login` does not apply.
- Console: open AWS Settings, then "AWS Console" on the project. The account menu (top right) switches between account sessions.
- CLI (needs AWS CLI 2.32.0 or later):

  ```sh
  aws login --profile botchat      # in the browser, choose the project account session
  export AWS_PROFILE=botchat       # set in ~/.zshrc
  aws sts get-caller-identity      # expect <project-account-id> and an assumed-role ARN
  ```

- Credentials are short-lived and renewed by `aws login`. No `~/.aws/credentials` file exists.
- `aws logout` ends the login session for every profile that shares it, not only the named one.
- Root: management account only, email `<root email>`, MFA on, no access keys. Use only for billing or closing the account. Project accounts have no root sign-in.

## Region

- Everything lives in `us-east-1`.
- The service control policy `AdvancedModeRegionRestrictionSecurityControlPolicy` limits Regions for the whole organization: `us-east-1` and `us-east-2` are open, `us-west-2` allows a few global services, all others are denied.
- Edit it only from the management account: AWS Organizations, Policies, Service control policies. To open another Region, add it to the `RegionFloor` statement's list.
- An error containing "explicit deny in a service control policy" almost always means the request went to a blocked Region.

## Cost guardrails

- Budget `botchat-monthly`: $10/month until Step 13, then $50/month (see Step 13.1); email at 50% actual and 100% forecast.
- The budget covers the project account only. Per-project spend limits are not available with advanced features active, so this budget is the only cost alarm.
- Expected spend: cents per month for SNS, SQS and Lambda at this project's volume. The EC2 instance and RDS from Step 13 are most of the bill: about $120/month running all the time, about $10/month stopped.
- Nothing stops the instance or the database automatically: run `./scripts/down.sh` when you finish (see `deploy.md`). A forgotten instance shows up as about $3.50 a day.

## Service permissions (from Steps 11 and 13)

- Policy `botchat-game-publisher`: may only `sns:Publish` to `game-events`.
- Policy `botchat-chat-consumer`: may only receive/delete on `level-updates` and `chat-notices`.
- Both are attached to the role `botchat-instance`, together with `AmazonSSMManagedInstanceCore` for Session Manager.
- No access keys exist: the instance metadata service (IMDSv2) hands out short-lived credentials for that role, to every pod that can reach it.

## If something looks wrong

1. Check the budget email and the Billing console's cost by service.
2. `aws iam list-users`: expect none (this project needs no IAM users or access keys).
3. `aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent'`: expect `0`.
4. CloudTrail event history for unfamiliar API calls.
5. Unexpected "access denied": confirm the account with `aws sts get-caller-identity` and the Region with `aws configure get region` before changing any permissions.
