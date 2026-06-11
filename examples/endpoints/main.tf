provider "aws" {
}

locals {
  name           = "shell-endpoints"
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

# =============================================================================
# Variant 1: Public Function URL (no auth)
# =============================================================================

module "public" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-public"
  runtime      = "provided.al2023"
  handler      = "handler.health"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn
  ]
}

resource "aws_lambda_function_url" "public" {
  function_name      = module.public.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
    max_age       = 300
  }
}

# =============================================================================
# Variant 2: IAM-authenticated Function URL
# =============================================================================

variable "allowed_principals" {
  type        = list(string)
  description = "IAM principal ARNs allowed to invoke the private function URL"
  default     = []
}

module "private" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"

  source_dir   = "./app"
  name         = "${local.name}-private"
  runtime      = "provided.al2023"
  handler      = "handler.echo_request"
  architecture = local.arch

  layers = [
    module.runtime.layer_arn,
    module.jq.layer_arn
  ]
}

resource "aws_lambda_function_url" "private" {
  function_name      = module.private.function_name
  authorization_type = "AWS_IAM"
}

resource "aws_lambda_permission" "private_invoke" {
  for_each = toset(var.allowed_principals)

  function_name          = module.private.function_name
  function_url_auth_type = "AWS_IAM"
  action                 = "lambda:InvokeFunctionUrl"
  principal              = each.value
  statement_id           = "AllowInvoke-${md5(each.value)}"
}

# =============================================================================
# Variant 3: Custom domain via Route53 + CloudFront
# =============================================================================

# Uncomment and configure for custom domain:
#
# locals {
#   domain_name = "api.example.com"
#   zone_name   = "example.com"
# }
#
# module "custom_domain" {
#   source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"
#
#   source_dir   = "./app"
#   name         = "${local.name}-custom"
#   runtime      = "provided.al2023"
#   handler      = "handler.timestamp"
#   architecture = local.arch
#
#   layers = [
#     module.runtime.layer_arn,
#     module.jq.layer_arn
#   ]
# }
#
# resource "aws_lambda_function_url" "custom_domain" {
#   function_name      = module.custom_domain.function_name
#   authorization_type = "NONE"
# }
#
# data "aws_route53_zone" "this" {
#   name = local.zone_name
# }
#
# # ACM certificate (must be in us-east-1 for CloudFront)
# resource "aws_acm_certificate" "this" {
#   provider          = aws.us_east_1
#   domain_name       = local.domain_name
#   validation_method = "DNS"
# }
#
# resource "aws_route53_record" "cert_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       type   = dvo.resource_record_type
#       record = dvo.resource_record_value
#     }
#   }
#
#   zone_id = data.aws_route53_zone.this.zone_id
#   name    = each.value.name
#   type    = each.value.type
#   ttl     = 300
#   records = [each.value.record]
# }
#
# resource "aws_acm_certificate_validation" "this" {
#   provider                = aws.us_east_1
#   certificate_arn         = aws_acm_certificate.this.arn
#   validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
# }
#
# resource "aws_cloudfront_distribution" "this" {
#   enabled = true
#   aliases = [local.domain_name]
#
#   origin {
#     domain_name = replace(aws_lambda_function_url.custom_domain.function_url, "/(https://|/)/", "")
#     origin_id   = "lambda-url"
#
#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "https-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }
#
#   default_cache_behavior {
#     target_origin_id       = "lambda-url"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD"]
#     cached_methods         = ["GET", "HEAD"]
#
#     forwarded_values {
#       query_string = true
#       cookies { forward = "none" }
#     }
#
#     min_ttl     = 0
#     default_ttl = 60
#     max_ttl     = 300
#   }
#
#   viewer_certificate {
#     acm_certificate_arn      = aws_acm_certificate.this.arn
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1.2_2021"
#   }
#
#   restrictions {
#     geo_restriction { restriction_type = "none" }
#   }
# }
#
# resource "aws_route53_record" "this" {
#   zone_id = data.aws_route53_zone.this.zone_id
#   name    = local.domain_name
#   type    = "A"
#
#   alias {
#     name                   = aws_cloudfront_distribution.this.domain_name
#     zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
#     evaluate_target_health = false
#   }
# }

# =============================================================================
# Variant 4: API Gateway integration
# =============================================================================

# Uncomment to expose via API Gateway with usage plans and API keys:
#
# module "api" {
#   source = "git::https://github.com/ql4b/terraform-aws-rest-api.git?ref=v1.0.0"
#
#   name   = local.name
#   stages = ["live"]
#
#   create_usage_plan = true
# }
#
# module "api_handler" {
#   source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.1.0"
#
#   source_dir   = "./app"
#   name         = "${local.name}-api"
#   runtime      = "provided.al2023"
#   handler      = "handler.health"
#   architecture = local.arch
#
#   layers = [
#     module.runtime.layer_arn,
#     module.jq.layer_arn
#   ]
# }
#
# # API Gateway → Lambda integration
# resource "aws_api_gateway_resource" "health" {
#   rest_api_id = module.api.rest_api_ids["live"]
#   parent_id   = module.api.root_resource_ids["live"]
#   path_part   = "health"
# }
#
# resource "aws_api_gateway_method" "health" {
#   rest_api_id   = module.api.rest_api_ids["live"]
#   resource_id   = aws_api_gateway_resource.health.id
#   http_method   = "GET"
#   authorization = "NONE"
# }
#
# resource "aws_api_gateway_integration" "health" {
#   rest_api_id             = module.api.rest_api_ids["live"]
#   resource_id             = aws_api_gateway_resource.health.id
#   http_method             = aws_api_gateway_method.health.http_method
#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = module.api_handler.invoke_arn
# }
#
# resource "aws_lambda_permission" "apigw" {
#   action        = "lambda:InvokeFunction"
#   function_name = module.api_handler.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${module.api.execution_arns["live"]}/*/*"
# }

# --- Outputs ---

output "endpoints" {
  value = {
    public = {
      authorization_type = aws_lambda_function_url.public.authorization_type
      url                = aws_lambda_function_url.public.function_url
      name               = aws_lambda_function_url.public.function_name
      arn                = aws_lambda_function_url.public.function_arn
      region             = aws_lambda_function_url.public.region
    }
    private = {
      authorization_type = aws_lambda_function_url.private.authorization_type
      url                = aws_lambda_function_url.private.function_url
      name               = aws_lambda_function_url.private.function_name
      arn                = aws_lambda_function_url.private.function_arn
    }
  }
}

# output "public_url" {
#   value = aws_lambda_function_url.public.function_url
# }

# output "private_url" {
#   value = aws_lambda_function_url.private.function_url
# }
