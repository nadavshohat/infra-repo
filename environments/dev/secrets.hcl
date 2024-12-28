locals {
  environment = "dev"
}

inputs = {
  secrets_manager = {
    enabled     = true
    name_prefix = "app/${local.environment}/microstore"
    description = "DocumentDB credentials for ${local.environment} environment"
    
    # Policy configuration
    create_policy       = true
    block_public_policy = true
    
    # Version configuration
    create_random_password = false
    ignore_secret_changes  = true
    
    # Rotation configuration
    enable_rotation = false
    
    # Recovery window
    recovery_window_in_days = 7
    
    # Tags
    tags = {
      Environment = local.environment
      Terraform   = "true"
      Service     = "documentdb"
      Project     = "microstore"
    }
  }
} 