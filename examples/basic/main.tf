provider "aws" {
}

# module "label" {
#   source  = "cloudposse/label/null"
#   version = "0.25.0"

#   name = "lambda-shell-layer-example"
# }

module "runtime" {
  source = "../../"

  name = "shell-runtime"
  # context = module.label.context
  architecture = "arm64" # "x86_64" # "arm64"
}

module "app" {
  source  = "ql4b/lambda-function/aws"
  version = "~> 1.2"

  source_dir = "./app"

  name = "shell-handler"

  runtime      = "provided.al2023"
  handler      = "handler.run"
  architecture = "arm64"

  layers = [
    module.runtime.layer_arn,
    # module.jq.layer_arn # optional
  ]

  depends_on = [
    module.runtime,
    # module.jq # optional
  ]
}

output "runtime" {
  value = module.runtime
}

output "app" {
  value = module.app
}
