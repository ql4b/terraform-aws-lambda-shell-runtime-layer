# Complete Example

Multiple shell Lambda functions demonstrating layer composition — each function uses a different combination of tool layers from [lambda-shell-layers](https://github.com/ql4b/lambda-shell-layers).

## What it demonstrates

- Composing multiple layers per function
- Pulling pre-built layer zips from GitHub Releases via `source_url`
- One handler file with multiple exported functions
- Each Lambda gets only the layers it needs

## Architecture

```
handler.sh
├── weather()   → runtime
├── events()    → runtime + jq
├── id()        → runtime + jq + uuid
├── runtimes()  → runtime + jq + htmlq
└── status()    → runtime + jq + http-cli
```

All layers are fetched from GitHub Releases:

```
https://github.com/ql4b/lambda-shell-layers/releases/download/<version>/<tool>-<arch>-layer.zip
```

## Usage

```bash
terraform init
terraform apply
```

Invoke each function:

```bash
aws lambda invoke --function-name shell-lambda-with-layers-weather /dev/stdout
aws lambda invoke --function-name shell-lambda-with-layers-events /dev/stdout
aws lambda invoke --function-name shell-lambda-with-layers-id /dev/stdout
aws lambda invoke --function-name shell-lambda-with-layers-runtimes /dev/stdout
aws lambda invoke --function-name shell-lambda-with-layers-status /dev/stdout
```

## Functions

| Function | Handler | Layers | Description |
|----------|---------|--------|-------------|
| weather | `handler.weather` | runtime | curl only (built-in) |
| events | `handler.events` | runtime, jq | GitHub events parsed with jq |
| id | `handler.id` | runtime, jq, uuid | Generate UUID, return as JSON |
| runtimes | `handler.runtimes` | runtime, jq, htmlq | Scrape AWS docs for Lambda runtimes |
| status | `handler.status` | runtime, jq, http-cli | HTTP status check with http-cli |

## Configuration

Switch architecture and layer version in `main.tf`:

```hcl
locals {
  arch           = "x86_64" # arm64|x86_64
  layers_version = "v0.0.4"
}
```

All layers and functions will rebuild for the target architecture.
