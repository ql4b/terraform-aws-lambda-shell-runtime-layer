# Endpoints Example

Shell Lambda functions exposed as HTTP endpoints — from a simple public URL to a custom domain with CDN, or behind API Gateway with usage plans.

## Variants

### 1. Public Function URL (no auth)

The simplest way to expose a Lambda as an HTTP endpoint:

```hcl
resource "aws_lambda_function_url" "public" {
  function_name      = module.public.function_name
  authorization_type = "NONE"
}
```

Result: a public `https://<id>.lambda-url.<region>.on.aws/` endpoint.

```bash
curl https://abc123.lambda-url.eu-central-1.on.aws/
# {"status":"ok","ts":"2026-06-10T10:00:00Z"}
```

### 2. IAM-authenticated Function URL

Requires AWS SigV4 signing to invoke — useful for service-to-service calls:

```hcl
resource "aws_lambda_function_url" "private" {
  function_name      = module.private.function_name
  authorization_type = "AWS_IAM"
}
```

Grant access to specific principals:

```hcl
allowed_principals = [
  "arn:aws:iam::123456789012:role/my-service-role"
]
```

Invoke with curl using SigV4 (service name is `lambda`):

```bash
eval $(aws sts get-session-token  \
    | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)"')
```

```bash
curl --aws-sigv4 "aws:amz:eu-central-1:lambda" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    https://xyz789.lambda-url.eu-central-1.on.aws/
```

If using an assumed role:

```bash
eval $(aws sts assume-role \
    --role-arn arn:aws:iam::123456789012:role/my-role \
    --role-session-name test \
    | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)"')

curl --aws-sigv4 "aws:amz:eu-central-1:lambda" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    https://xyz789.lambda-url.eu-central-1.on.aws/
```

### 3. Custom Domain (Route53 + CloudFront)

Put a custom domain in front of the Function URL:

```
api.example.com → CloudFront → Lambda Function URL
```

Provides:
- Custom domain with SSL (ACM certificate)
- Edge caching for GET responses
- Global distribution

See commented section in `main.tf` — uncomment and set your domain/zone.

### 4. API Gateway

Full-featured API with usage plans, API keys, throttling, and stages:

```
https://api-id.execute-api.region.amazonaws.com/live/health
```

Provides:
- API key authentication
- Rate limiting and quotas
- Multiple stages (live, staging)
- Request/response transformation
- Access logging

Uses [terraform-aws-rest-api](https://github.com/ql4b/terraform-aws-rest-api) module. See commented section in `main.tf`.

## When to use what

| Variant | Use case |
|---------|----------|
| Public URL | Webhooks, health checks, public APIs |
| IAM URL | Internal service-to-service, machine clients |
| Custom domain | Production public APIs, branded endpoints |
| API Gateway | API key management, throttling, multiple consumers |

## Usage

```bash
terraform init
terraform apply
```

Test the public endpoint:

```bash
curl $(terraform output -raw public_url)
```

Test the IAM endpoint:

```bash
aws lambda invoke-url --function-name shell-endpoints-private /dev/stdout
```
