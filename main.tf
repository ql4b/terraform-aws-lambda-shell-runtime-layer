locals {
  arch_file = {
    "arm64"  = "arm64"
    "x86_64" = "amd64"
  }
}

module "runtime" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-layer.git?ref=v1.1.0"

  context = module.this.context

  description = "Shell-first Lambda runtime (${var.architecture})"

  compatible_architectures = [var.architecture]
  compatible_runtimes      = ["provided.al2023"]

  filename              = "${path.module}/runtime/bootstrap-${local.arch_file[var.architecture]}.zip"
  enable_ssm_parameters = false

}
