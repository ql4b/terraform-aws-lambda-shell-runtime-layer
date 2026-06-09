# AWS Services Example

Interact with AWS services directly from shell Lambda functions using `curl --aws-sigv4` — no SDK required.

## How it works

Lambda provides IAM credentials via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). Since curl 7.75+, the `--aws-sigv4` flag handles Signature Version 4 signing natively:

```bash
curl -sSf \
    --aws-sigv4 "aws:amz:${AWS_REGION}:<service>" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
    "https://<service>.${AWS_REGION}.amazonaws.com/"
```

No AWS CLI, no SDK, no dependencies beyond curl (which is built into `provided.al2023`).

## Functions

| Function | Service | Layers | Description |
|----------|---------|--------|-------------|
| buckets | S3 | runtime | List S3 buckets (XML response) |
| put_item | DynamoDB | runtime, jq, uuid | Create item with generated UUID |
| publish | SNS | runtime | Publish message to topic |
| get_param | SSM | runtime, jq | Read parameter value |
| send_message | SQS | runtime, jq | Send message to queue |

Most functions need only the runtime layer. jq is added only when building or parsing JSON payloads, uuid only when generating IDs.

## SigV4 Signing

The `--aws-sigv4` flag format:

```
--aws-sigv4 "aws:amz:<region>:<service>"
```

Combined with `--user` for credentials and the security token header, this is all that's needed to authenticate against any AWS service API.

### Service-specific notes

- **S3** — Returns XML; query-string API
- **DynamoDB** — JSON via `X-Amz-Target: DynamoDB_20120810.<Action>`
- **SNS** — Form-encoded parameters (`Action=Publish&TopicArn=...&Message=...`)
- **SSM** — JSON via `X-Amz-Target: AmazonSSM.<Action>`
- **SQS** — JSON via `X-Amz-Target: AmazonSQS.<Action>`

## Usage

```bash
terraform init
terraform apply
```

Invoke:

```bash
aws lambda invoke --function-name shell-aws-services-buckets /dev/stdout
aws lambda invoke --function-name shell-aws-services-put-item /dev/stdout
aws lambda invoke --function-name shell-aws-services-publish /dev/stdout
aws lambda invoke --function-name shell-aws-services-get-param /dev/stdout
aws lambda invoke --function-name shell-aws-services-send-message /dev/stdout
```

## Why not AWS CLI?

| | curl + sigv4 | AWS CLI |
|--|---|---|
| Cold start | ~22ms | 500ms+ |
| Layer size | 0 (built-in) | 50MB+ |
| Dependencies | none | Python runtime |
| Flexibility | full HTTP control | CLI abstractions |
