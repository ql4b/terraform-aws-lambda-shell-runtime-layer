# Basic Example

Minimal shell Lambda function using only the custom runtime layer.

## What it demonstrates

- Shell script as Lambda handler
- Custom `provided.al2023` runtime with the shell bootstrap layer
- Using built-in `curl` (no additional layers needed)

## Architecture

```
handler.sh (curl) → runtime layer → Lambda (provided.al2023)
```

## Usage

```bash
terraform init
terraform apply
```

Invoke:

```bash
aws lambda invoke --function-name shell-handler /dev/stdout
```

## Handler

```bash
run () {
    curl -Ss https://wttr.in/?format=3
}
```

The runtime layer provides the bootstrap that sources `handler.sh` and calls the function specified in the `handler` setting (e.g. `handler.run` → sources `handler.sh`, calls `run`).
