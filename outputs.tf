output "layer_arn" {
  description = "Lambda layer ARN"
  value       = module.runtime.layer_arn
}

output "layer_version" {
  description = "Lambda layer version"
  value       = module.runtime.layer_version
}
