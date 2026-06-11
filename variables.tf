variable "architecture" {
  type        = string
  description = "architecture the lambda layer is compatible with"
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Architecture must be either x86_64 or arm64."
  }
}
