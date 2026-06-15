provider "aws" {
}

locals {
  name           = "shell-lambda-with-layers"
  layers_version = "v0.0.4" # check https://github.com/ql4b/lambda-shell-layers/releases for latest
  arch           = "arm64"  # arm64|x86_64
  layers_base    = "https://github.com/ql4b/lambda-shell-layers/releases/download/${local.layers_version}"
}

# --- Layers ---

module "runtime" {
  source = "../../"

  name         = "${local.name}-runtime"
  architecture = local.arch
}

module "qrencode" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.2.0"

  name                     = "${local.name}-qrencode"
  source_url               = "${local.layers_base}/qrencode-${local.arch}-layer.zip"
  compatible_architectures = [local.arch]
  enable_ssm_parameters    = false
}

module "jq" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.2.0"

  name                     = "${local.name}-jq"
  source_url               = "${local.layers_base}/jq-${local.arch}-layer.zip"
  compatible_architectures = [local.arch]
  enable_ssm_parameters    = false
}

module "uuid" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.2.0"

  name                     = "${local.name}-uuid"
  source_url               = "${local.layers_base}/uuid-${local.arch}-layer.zip"
  compatible_architectures = [local.arch]
  enable_ssm_parameters    = false
}

module "htmlq" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.2.0"

  name                     = "${local.name}-htmlq"
  source_url               = "${local.layers_base}/htmlq-${local.arch}-layer.zip"
  compatible_architectures = [local.arch]
  enable_ssm_parameters    = false
}

module "http_cli" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.2.0"

  name                     = "${local.name}-http-cli"
  source_url               = "${local.layers_base}/http-cli-${local.arch}-layer.zip"
  compatible_architectures = [local.arch]
  enable_ssm_parameters    = false
}

# --- Functions ---

# curl only (no extra layers)
module "weather" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-weather"
  runtime      = "provided.al2023"
  handler      = "handler.weather"
  architecture = local.arch

  layers = [module.runtime.layer_arn]
}

# jq layer
module "events" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-events"
  runtime      = "provided.al2023"
  handler      = "handler.events"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn
  ]
}

# uuid + jq layers
module "id" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-id"
  runtime      = "provided.al2023"
  handler      = "handler.id"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn,
    module.uuid.layer_arn
  ]
}

# htmlq + jq layers
module "runtimes" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-runtimes"
  runtime      = "provided.al2023"
  handler      = "handler.runtimes"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn,
    module.htmlq.layer_arn
  ]
}

# http-cli + jq layers
module "status" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-status"
  runtime      = "provided.al2023"
  handler      = "handler.status"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn,
    module.http_cli.layer_arn
  ]
}

module "qr" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-qr"
  runtime      = "provided.al2023"
  handler      = "handler.qr"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.qrencode.layer_arn,
  ]
}

# --- Outputs ---

output "functions" {
  value = {
    weather  = module.weather
    events   = module.events
    id       = module.id
    runtimes = module.runtimes
    status   = module.status
    qr       = module.qr
  }
}

output "layers" {
  value = {
    runtime  = module.runtime
    jq       = module.jq
    uuid     = module.uuid
    htmlq    = module.htmlq
    http_cli = module.http_cli
  }
}
