inputs = {
    environment = "dev"
  # DocumentDB Configuration
  documentdb = {
    enabled = true
    cluster_size = 1  # Dev environment, single instance
    instance_class = "db.t3.medium"
    engine_version = "4.0.0"
    storage_encrypted = true
    deletion_protection = false  # Dev environment, easier cleanup
    skip_final_snapshot = true  # Dev environment
    
    # Database credentials
    master_username = "microstore"
    master_password = "initial-password-to-be-changed"  # This will be replaced by our random password
    
    # Backup settings
    retention_period = 5
    preferred_backup_window = "07:00-09:00"
    preferred_maintenance_window = "Mon:22:00-Mon:23:00"
    
    # Monitoring
    enabled_cloudwatch_logs_exports = ["audit", "profiler"]
    
    # Tags
    tags = {
      Environment = "dev"
      Service     = "documentdb"
    }
  }
} 