# prod environment
#   terraform init -reconfigure -backend-config="config/backend-prod.hcl"
#   terraform plan -var-file="config/prod.tfvars" -input=false
# Secrets are NOT stored here. Set the DB password first:
#   $env:TF_VAR_administrator_password = "<strong password>"

environment        = "prod"
prefix             = "proact"
location           = "uksouth"
vnet_address_space = ["10.2.0.0/16"]

redis_sku      = "Balanced_B1" # case-sensitive
redis_capacity = 1             # legacy placeholder, ignored by azurerm_managed_redis

office_ip = "135.129.124.220"


# Extra Key Vault secret URIs only. DB/AI/Redis/Storage URIs are generated in main.tf.
app_secrets_kv_uris = {}

# -----------------------------------------------------------------------------
# Database network access.
# The private endpoint is created, and the container apps reach the database
# through it (the privatelink DNS zone makes the normal server name resolve to a
# private IP inside the VNet). Public access is still ON, with the office-IP rule.
# When you are ready to close it, change db_public_access_enabled to false and apply.
# Do NOT toggle it only in the portal: the next apply would switch it back on.
# -----------------------------------------------------------------------------
db_private_endpoint_enabled = true
db_public_access_enabled    = true

# -----------------------------------------------------------------------------
# Azure OpenAI: gpt-5 and gpt-4o are deployed side by side.
# Each deployment has its own quota (capacity is in thousands of tokens per minute),
# and the apps get one AI-DEPLOYMENT-<NAME> variable per deployment.
# Verify both models are deployable in East US before applying (gpt-4o is a legacy model; see README).
# -----------------------------------------------------------------------------
ai_deployments = {
  "gpt-5" = {
    model_name    = "gpt-5"
    model_version = "2025-08-07"
    sku           = "GlobalStandard"
    capacity      = 10
  }
  "gpt-4o" = {
    model_name    = "gpt-4o"
    model_version = "2024-11-20"
    sku           = "GlobalStandard"
    capacity      = 10
  }
}

# -----------------------------------------------------------------------------
# Container apps: both pull from the same registry over a private endpoint
# -----------------------------------------------------------------------------
container_apps = {
  "api-container" = {
    ingress_enabled = true
    target_port     = 3000
    cpu             = 1
    memory          = "2Gi"
    min_replicas    = 2
    max_replicas    = 10
  }
  "worker-container" = {
    cpu          = 1
    memory       = "2Gi"
    min_replicas = 1
    max_replicas = 5
  }
}

acr_private_link_enabled = true # registry becomes Premium, reached over a private endpoint
acr_allowed_ip_ranges    = []   # add e.g. ["203.0.113.4/32"] to let a build agent push; empty = no public access

# -----------------------------------------------------------------------------
# Database: starts on Burstable and steps up/down this ladder from alerts.
# Storage starts at 128 GB and auto-grows (it can never shrink).
# CPU credits exist only on B_ SKUs; GP_ SKUs have none.
# -----------------------------------------------------------------------------
db_sku        = "B_Standard_B2s"
db_storage_mb = 131072

db_scaling = {
  enabled = true
  sku_ladder = [
    "B_Standard_B2s",
    "B_Standard_B2ms",
    "B_Standard_B4ms",
    "GP_Standard_D4s_v3",
    "GP_Standard_D8s_v3",
  ]
  scale_up_cpu_percent   = 80 # average CPU over 15 min
  scale_down_cpu_percent = 20 # average CPU over 6 h
  cpu_credits_low        = 50 # Burstable only: credits remaining
  cooldown_up_minutes    = 30
  cooldown_down_minutes  = 360
}

# -----------------------------------------------------------------------------
# Frontend: native autoscale changes the instance count (2-6);
# the runbook changes the tier along this ladder.
# -----------------------------------------------------------------------------
webapp_sku = "P1v3"

webapp_scaling = {
  enabled    = true
  sku_ladder = ["P1v3", "P2v3", "P3v3"]

  min_instances         = 2
  max_instances         = 6
  scale_out_cpu_percent = 70 # add an instance
  scale_in_cpu_percent  = 30 # remove an instance

  scale_up_cpu_percent   = 85 # average CPU over 30 min even after scaling out: next tier
  scale_down_cpu_percent = 20 # average CPU over 12 h: previous tier
  cooldown_up_minutes    = 60
  cooldown_down_minutes  = 720
}
