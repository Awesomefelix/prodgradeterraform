locals {
  # Key Vault secret names may only contain letters, digits and hyphens
  secret_names = {
    for k in keys(var.deployments) : k => "AI-DEPLOYMENT-${upper(replace(k, "/[^A-Za-z0-9]/", "-"))}"
  }
}
