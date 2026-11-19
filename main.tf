locals {
  arch_file = {
    "arm64"  = "arm64"
    "x86_64" = "amd64"
  }
}

module "runtime" {
  source  = "ql4b/lambda-layer/aws"
  version = "~> 1.2"

  context = module.this.context

  description = "Shell-first Lambda runtime (${var.architecture})"

  compatible_architectures = [var.architecture]
  compatible_runtimes      = ["provided.al2023"]

  filename              = "${path.module}/runtime/bootstrap-${local.arch_file[var.architecture]}.zip"
  enable_ssm_parameters = false

}
