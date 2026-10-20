output "deployment_names" {
  value       = sort(keys(var.deployments))
  description = "Names of the model deployments"
}

output "deployment_secret_names" {
  value       = sort(values(local.secret_names))
  description = "Key Vault secret names that hold each deployment name"
}
