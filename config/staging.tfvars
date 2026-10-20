# staging environment
#   terraform init -reconfigure -backend-config="config/backend-staging.hcl"
#   terraform plan -var-file="config/staging.tfvars" -input=false
# Secrets are NOT stored here. Set the DB password first:
#   $env:TF_VAR_administrator_password = "<strong password>"

environment        = "stg"
prefix             = "proact"
location           = "uksouth"
vnet_address_space = ["10.1.0.0/16"]

webapp_sku     = "S1"
db_sku         = "B_Standard_B2s"
redis_sku      = "Balanced_B0" # case-sensitive
redis_capacity = 1             # legacy placeholder, ignored by azurerm_managed_redis

office_ip = "135.129.124.220"


# Extra Key Vault secret URIs only. DB/AI/Redis/Storage URIs are generated in main.tf.
app_secrets_kv_uris = {}
