# terraform-aws-lambda-shell-runtime-layer

A Terraform module that publishes a Lambda Layer containing a custom runtime for executing shell functions on AWS Lambda with minimal cold-start overhead.

```bash
run () {
    curl -Ss https://wttr.in/?format=3
}
```

That's a complete Lambda function. No SDK, no framework, no build step.


![diagram](https://raw.githubusercontent.com/ql4b/terraform-aws-lambda-shell-runtime-layer/main/doc/diagram.jpg)

## How it works

A custom AWS Lambda runtime is a [program that runs a Lambda function's handler method when the function is invoked](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html).

This module ships pre-built runtime binaries (Go bootstrap) and publishes them as a Lambda Layer. The runtime:

1. Starts as `/var/runtime/bootstrap` in the Lambda execution environment
2. Polls the [Lambda Runtime API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html) for invocation events
3. Sources your handler script (e.g. `handler.sh`)
4. Calls the specified function (e.g. `run`) with the event payload
5. Returns the function's stdout as the response via the Runtime API

Publishing the runtime as a layer keeps your function deployment packages tiny (just your shell scripts), makes deployments fast, and adds negligible overhead from the layer mount.

## Usage

```hcl
# Publish the runtime layer (once per region)
module "shell_runtime" {
  source  = "ql4b/lambda-shell-runtime-layer/aws"
  version = "~> 1.0"

  name         = "shell-runtime"
  architecture = "arm64"
}

# Use it in your functions
module "my_function" {
  source  = "ql4b/lambda-function/aws"
  version = "~> 1.0"

  source_dir = "./app"
  name       = "my-function"

  runtime      = "provided.al2023"
  handler      = "handler.run"
  architecture = "arm64"

  layers = [
    module.shell_runtime.layer_arn,
  ]
}
```

The `handler` format is `<file>.<function>` — so `handler.run` means: source `handler.sh`, call `run()`.

## Multiple functions, one runtime

The layer is published once and shared across functions:

```hcl
module "shell_runtime" {
  source  = "ql4b/lambda-shell-runtime-layer/aws"
  version = "~> 1.0"

  name         = "shell-runtime"
  architecture = "arm64"
}

module "function_a" {
  source  = "ql4b/lambda-function/aws"
  version = "~> 1.0"

  source_dir   = "./app"
  name         = "function-a"
  runtime      = "provided.al2023"
  handler      = "handler.a"
  architecture = "arm64"
  layers       = [module.shell_runtime.layer_arn]
}

module "function_b" {
  source  = "ql4b/lambda-function/aws"
  version = "~> 1.0"

  source_dir   = "./app"
  name         = "function-b"
  runtime      = "provided.al2023"
  handler      = "handler.b"
  architecture = "arm64"
  layers       = [module.shell_runtime.layer_arn]
}
```

## Examples

See [`examples/`](./examples/) for working deployments:

| Example | Description |
|---------|-------------|
| [`basic`](./examples/basic/) | Minimal function with runtime layer only |
| [`endpoints`](./examples/endpoints/) | Function URLs (public + private) |
| [`aws-services`](./examples/aws-services/) | Functions calling S3, SNS, SSM, SQS, DynamoDB |
| [`complete`](./examples/complete/) | Multiple functions with different layer combinations |

```bash
cd examples/basic
terraform init
terraform apply
```

The basic example deploys a function with handler `handler.run` that calls `curl`:

```bash
#!/bin/bash

set -euo pipefail

run () {
    curl -Ss https://wttr.in/?format=3
}
```

> Note: `curl` is available in `provided.al2023`. For `jq` or other tools, add them as a separate layer.

## What's available in the execution environment

With `provided.al2023`, your functions run on a minimal [Amazon Linux 2023](https://aws.amazon.com/blogs/compute/introducing-the-amazon-linux-2023-runtime-for-aws-lambda/) environment. This gives you a base set of utilities out of the box — no layers needed:

- `curl` (with `--aws-sigv4` support)
- `bash`, `sh`
- `cat`, `grep`, `sed`, `awk`, `cut`, `sort`, `head`, `tail`
- `date`, `env`, `mktemp`, `base64`

This is the [custom runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html) contract: AWS provides the OS and the Runtime API, you provide the bootstrap and your handler. The runtime layer handles the bootstrap, so your function packages contain only shell scripts.

For anything beyond what the OS ships — JSON processing, HTML parsing, UUID generation — you add tool layers.

## Adding Tool Layers

The runtime layer provides the shell bootstrap. To add CLI tools (jq, htmlq, uuid, etc.), compose additional layers from [lambda-shell-layers](https://github.com/ql4b/lambda-shell-layers):

```hcl
module "shell_runtime" {
  source  = "ql4b/lambda-shell-runtime-layer/aws"
  version = "~> 1.0"

  name         = "shell-runtime"
  architecture = "arm64"
}

module "jq" {
  source  = "ql4b/lambda-layer/aws"
  version = "~> 1.0"

  name       = "jq"
  source_url = "https://github.com/ql4b/lambda-shell-layers/releases/download/v0.0.4/jq-arm64-layer.zip"

  compatible_architectures = ["arm64"]
  enable_ssm_parameters    = false
}

module "my_function" {
  source  = "ql4b/lambda-function/aws"
  version = "~> 1.0"

  source_dir   = "./app"
  name         = "my-function"
  runtime      = "provided.al2023"
  handler      = "handler.run"
  architecture = "arm64"

  layers = [
    module.shell_runtime.layer_arn,
    module.jq.layer_arn,
  ]
}
```

Each function gets only the layers it needs — keeping deployment packages small and cold starts fast.

See [`examples/complete/`](./examples/complete/) for a full example with multiple functions and layer combinations.

### Calling AWS Services without SDK

See [`examples/aws-services/`](./examples/aws-services/) — interact with S3, DynamoDB, SNS, SSM, and SQS directly from shell using `curl --aws-sigv4`. No AWS CLI or SDK required, just the built-in curl from `provided.al2023`.

### HTTP Endpoints

See [`examples/endpoints/`](./examples/endpoints/) — expose shell functions as HTTP endpoints via Lambda Function URLs (public or IAM-authenticated), custom domains with CloudFront, or API Gateway with usage plans.

## Local Testing with Docker

Test your shell functions locally without deploying to AWS. Two Dockerfiles are provided:

- `basic.Dockerfile` — runtime only (curl available from al2023)
- `Dockerfile` — runtime + tool layers (jq, uuid, htmlq)

### Basic (runtime only)

```bash
docker build -f basic.Dockerfile --platform linux/arm64 -t shell-runtime-basic .
docker run --rm --platform linux/arm64 -p 9000:8080 shell-runtime-basic
```

```bash
curl -s -XPOST http://localhost:9000/2015-03-31/functions/function/invocations -d '{}'
```

### Complete (with layers)

```bash
docker build -f Dockerfile --platform linux/arm64 -t shell-runtime-complete .
docker run --rm --platform linux/arm64 -p 9000:8080 shell-runtime-complete
```

Default handler is `handler.weather`. Override to test other functions:

```bash
docker run --rm --platform linux/arm64 -p 9000:8080 shell-runtime-complete handler.id
docker run --rm --platform linux/arm64 -p 9000:8080 shell-runtime-complete handler.runtimes
```

Invoke:

```bash
curl -s -XPOST http://localhost:9000/2015-03-31/functions/function/invocations -d '{}'
```

> Note: The complete Dockerfile includes jq, uuid, htmlq, and qrencode layers. Handlers that require other layers (http-cli) won't work locally unless you add them to the Dockerfile.

## Architecture

The module ships pre-built runtime binaries for both architectures:

```
runtime/
├── bootstrap-arm64.zip    # Graviton (arm64) — recommended
├── bootstrap-amd64.zip    # Intel (x86_64)
├── main.go                # Runtime source code
├── go.mod
└── Makefile               # Build targets
```

The runtime source is available in [`runtime/`](./runtime/) — a minimal Go program that implements the Lambda Runtime API loop and shells out to your handler function.

`arm64` is recommended — it's 20% cheaper and generally faster on Lambda (Graviton2/3).

## Cold Start Performance

All values in milliseconds. Measured on `provided.al2023` with 128MB memory.

### `arm64` — runtime only ([`examples/aws-services`](./examples/aws-services/))

| Function | Layers | median | p90 | p99 | iqr | n |
|----------|--------|--------|-----|-----|-----|---|
| buckets | 1 (runtime) | 21.56 | 22.53 | 23.68 | 3.27 | 59 |
| publish | 1 (runtime) | 19.54 | 22.05 | 22.08 | 2.24 | 10 |
| get-param | 2 (runtime + jq) | 18.96 | 22.20 | 22.51 | 3.57 | 9 |
| send-message | 2 (runtime + jq) | 19.34 | 21.90 | 22.75 | 0.63 | 12 |
| put-item | 3 (runtime + jq + uuid) | 21.49 | 22.34 | 22.43 | 2.48 | 9 |

### `arm64` — with Function URLs ([`examples/endpoints`](./examples/endpoints/))

| Function | Layers | median | p90 | p99 | iqr | n |
|----------|--------|--------|-----|-----|-----|---|
| public | 2 (runtime + jq) | 19.05 | 22.29 | 22.58 | 2.71 | 24 |
| private | 2 (runtime + jq) | 19.24 | 22.04 | 22.44 | 1.79 | 16 |

### `arm64` — multiple tool layers ([`examples/complete`](./examples/complete/))

| Function | Layers | median | p90 | p99 | iqr | n |
|----------|--------|--------|-----|-----|-----|---|
| weather | 2 (runtime + jq) | 19.06 | 22.32 | 27.56 | 3.00 | 53 |
| events | 2 (runtime + jq) | 19.15 | 22.18 | 22.50 | 3.04 | 59 |
| id | 3 (runtime + jq + uuid) | 19.29 | 22.12 | 22.77 | 2.82 | 18 |
| runtimes | 3 (runtime + jq + htmlq) | 19.20 | 22.30 | 23.29 | 3.34 | 60 |
| status | 3 (runtime + jq + http-cli) | 19.98 | 22.26 | 22.79 | 2.82 | 32 |

### `x86_64` — multiple tool layers ([`examples/complete`](./examples/complete/))

| Function | Layers | median | p90 | p99 | iqr | n |
|----------|--------|--------|-----|-----|-----|---|
| weather | 1 (runtime) | 25.71 | 26.67 | 28.10 | 0.46 | 43 |
| events | 2 (runtime + jq) | 25.56 | 26.14 | 26.52 | 0.66 | 60 |
| id | 3 (runtime + jq + uuid) | 25.65 | 26.20 | 32.12 | 0.57 | 24 |
| runtimes | 3 (runtime + jq + htmlq) | 25.70 | 26.47 | 28.14 | 0.97 | 60 |
| status | 3 (runtime + jq + http-cli) | 25.54 | 26.50 | 28.79 | 0.93 | 28 |

### Key observations

- **arm64 is ~25% faster** than x86_64 on cold start (~19ms vs ~25ms median)
- **Layer count has negligible impact** — 1 layer vs 3 layers shows no meaningful difference
- **Handler complexity is irrelevant** — init only sources the file, doesn't execute the function
- **IQR < 4ms** across all configurations — cold starts are highly predictable

### Benchmark methodology

Cold starts are measured by forcing fresh execution environments ([lambda-benchmarks](https://github.com/ql4b/lambda-benchmarks)):

1. Update the function configuration (environment variable change) to invalidate all warm environments
2. Wait for propagation
3. Invoke 120 times concurrently (`parallel -j 60`) — Lambda provisions new environments for each concurrent request
4. Wait for CloudWatch logs to flush
5. Extract `Init Duration` from REPORT lines and compute stats with `datamash`

This produces real cold starts without artificial function updates between each invocation, giving a realistic distribution from a single burst.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_runtime"></a> [runtime](#module\_runtime) | git::https://github.com/ql4b/terraform-aws-lambda-layer.git | v1.1.0 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_architecture"></a> [architecture](#input\_architecture) | architecture the lambda layer is compatible with | `string` | `"arm64"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_layer_arn"></a> [layer\_arn](#output\_layer\_arn) | Lambda layer ARN |
| <a name="output_layer_version"></a> [layer\_version](#output\_layer\_version) | Lambda layer version |
<!-- END_TF_DOCS -->