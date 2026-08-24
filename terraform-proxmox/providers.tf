provider "proxmox" {
  pm_api_url = var.proxmox_endpoint

  # null (not "") when unset, so the provider falls back to the
  # PM_API_TOKEN_ID / PM_API_TOKEN_SECRET environment variables
  pm_api_token_id     = var.proxmox_api_token != "" ? var.proxmox_api_token : null
  pm_api_token_secret = var.proxmox_api_secret != "" ? var.proxmox_api_secret : null
  pm_tls_insecure     = var.proxmox_tls_insecure

  # Clones lock the source template; serialize them.
  pm_parallel = 1
  pm_timeout  = 600
}