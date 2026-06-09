provider "aws" {
}

locals {
  name           = "shell-aws-services"
  arch           = "arm64"
  layers_version = "v0.0.4" # check https://github.com/ql4b/lambda-shell-layers/releases for latest
  layers_base    = "https://github.com/ql4b/lambda-shell-layers/releases/download/${local.layers_version}"
}

# --- Layers ---

module "runtime" {
  source = "../../"

  name         = "${local.name}-runtime"
  architecture = local.arch
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

# --- Infrastructure ---

resource "aws_dynamodb_table" "this" {
  name         = "${local.name}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_sns_topic" "this" {
  name = "${local.name}-events"
}

resource "aws_sqs_queue" "this" {
  name = "${local.name}-queue"
}

resource "aws_ssm_parameter" "this" {
  name  = "/${local.name}/config"
  type  = "String"
  value = "hello-from-ssm"
}

# --- Functions ---

# List S3 buckets (curl only)
module "buckets" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-buckets"
  runtime      = "provided.al2023"
  handler      = "handler.buckets"
  architecture = local.arch

  layers = [module.runtime.layer_arn]
}

resource "aws_iam_role_policy" "buckets_s3" {
  name = "s3-list"
  role = module.buckets.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets"]
      Resource = "*"
    }]
  })
}

# Put item to DynamoDB (uuid + jq)
module "put_item" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-put-item"
  runtime      = "provided.al2023"
  handler      = "handler.put_item"
  architecture = local.arch

  environment_variables = {
    TABLE_NAME = aws_dynamodb_table.this.name
  }

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn,
    module.uuid.layer_arn
  ]
}

resource "aws_iam_role_policy" "put_item_dynamodb" {
  name = "dynamodb-put"
  role = module.put_item.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = aws_dynamodb_table.this.arn
    }]
  })
}

# Publish to SNS (curl only)
module "publish" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-publish"
  runtime      = "provided.al2023"
  handler      = "handler.publish"
  architecture = local.arch

  environment_variables = {
    TOPIC_ARN = aws_sns_topic.this.arn
  }

  layers = [module.runtime.layer_arn]
}

resource "aws_iam_role_policy" "publish_sns" {
  name = "sns-publish"
  role = module.publish.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.this.arn
    }]
  })
}

# Get SSM parameter (jq)
module "get_param" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-get-param"
  runtime      = "provided.al2023"
  handler      = "handler.get_param"
  architecture = local.arch

  environment_variables = {
    PARAM_NAME = aws_ssm_parameter.this.name
  }

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn
  ]
}

resource "aws_iam_role_policy" "get_param_ssm" {
  name = "ssm-get"
  role = module.get_param.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = aws_ssm_parameter.this.arn
    }]
  })
}

# Send SQS message (jq)
module "send_message" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-send-message"
  runtime      = "provided.al2023"
  handler      = "handler.send_message"
  architecture = local.arch

  environment_variables = {
    QUEUE_URL = aws_sqs_queue.this.url
  }

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn
  ]
}

resource "aws_iam_role_policy" "send_message_sqs" {
  name = "sqs-send"
  role = module.send_message.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.this.arn
    }]
  })
}

# --- Outputs ---

output "functions" {
  value = {
    buckets      = module.buckets
    put_item     = module.put_item
    publish      = module.publish
    get_param    = module.get_param
    send_message = module.send_message
  }
}
