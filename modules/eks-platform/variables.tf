# VPC Variables
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all private networks"
  type        = bool
  default     = true
}

variable "one_nat_gateway_per_az" {
  description = "Should be true if you want only one NAT Gateway per availability zone"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Should be true to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Should be true to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Should be true if you want to create a VPN Gateway"
  type        = bool
  default     = false
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

variable "subnet_bits" {
  description = "Number of additional bits with which to extend the VPC CIDR prefix when calculating subnet CIDRs (null means use default of 8)"
  type        = number
  default     = null
}

# EKS Variables
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "terraform-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_private_access" {
  description = "Whether the Amazon EKS private API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Whether to enable cluster creator admin permissions"
  type        = bool
  default     = true
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = any
  default     = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "aws_role_arn" {
  description = "ARN of the IAM role to assume when connecting to the cluster"
  type        = string
  default     = "arn:aws:iam::767397741479:role/TerraformRole"
}

# EKS Addons Variables
variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_ingress_nginx" {
  description = "Enable NGINX Ingress Controller"
  type        = bool
  default     = true
}

variable "ingress_nginx_namespace" {
  description = "Namespace for NGINX Ingress Controller"
  type        = string
  default     = "nginx"
}

variable "ingress_nginx_service_type" {
  description = "Service type for NGINX Ingress Controller"
  type        = string
  default     = "NodePort"
}

variable "ingress_class_name" {
  description = "Name of the ingress class"
  type        = string
  default     = "nginx"
}

variable "enable_cert_manager" {
  description = "Enable Cert Manager"
  type        = bool
  default     = true
}

variable "cert_manager_namespace" {
  description = "Namespace for Cert Manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_service_account" {
  description = "Service account name for Cert Manager"
  type        = string
  default     = "cert-manager"
}

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator"
  type        = bool
  default     = true
}

variable "external_secrets_namespace" {
  description = "Namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "Service account name for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "enable_argocd" {
  description = "Enable ArgoCD"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_helm_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "5.46.7"
}

variable "argocd_service_type" {
  description = "Service type for ArgoCD server"
  type        = string
  default     = "ClusterIP"
}

variable "ingress_alb" {
  description = "Shared ALB ingress configuration for NGINX controller"
  type = object({
    enabled = optional(bool, true)
    name = optional(string, "nginx-alb")
    namespace = optional(string, "ingress-nginx")
    service = optional(object({
      name = optional(string, "ingress-nginx-controller")
      port = optional(number, 80)
    }), {})
    path = optional(string, "/*")
    annotations = optional(map(string), {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/group.name"       = "shared"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/ssl-policy"       = "ELBSecurityPolicy-TLS-1-2-2017-01"
    })
  })
  default = {}
}

# Route53 Records Variables
variable "zone_name" {
  description = "The name of the hosted zone"
  type        = string
  default     = "nshohat.online"
}

variable "route53_records" {
  description = "List of Route53 records to create"
  type = map(object({
    name    = string
    type    = string
    ttl     = number
    records = list(string)
  }))
}

variable "aws_region" {
  description = "AWS region where the cluster is deployed"
  type        = string
  default     = "us-east-1"
}

# ACM Variables
variable "domain_name" {
  description = "Domain name for the ACM certificate"
  type        = string
  default = "nshohat.online"
}

variable "validation_method" {
  description = "Which method to use for validation, DNS or EMAIL"
  type        = string
  default     = "DNS"
}

variable "subject_alternative_names" {
  description = "Subject alternative domain names"
  type        = list(string)
  default     = []
}

variable "wait_for_validation" {
  description = "Whether to wait for the validation to complete"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "documentdb" {
  description = "DocumentDB cluster configuration"
  type = object({
    enabled                         = bool
    cluster_size                    = number
    instance_class                  = string
    engine_version                  = string
    master_username                 = string
    master_password                 = string
    storage_encrypted              = bool
    retention_period               = number
    skip_final_snapshot           = bool
    deletion_protection           = bool
    preferred_backup_window       = string
    preferred_maintenance_window  = string
    enabled_cloudwatch_logs_exports = list(string)
    tags                          = map(string)
  })
  default = null
}

variable "secrets_manager" {
  description = "Configuration for AWS Secrets Manager"
  type = object({
    enabled = bool
    name_prefix = string
    description = string
    recovery_window_in_days = optional(number, 30)
    
    # Policy configuration
    create_policy = optional(bool, true)
    block_public_policy = optional(bool, true)
    policy_statements = optional(map(object({
      sid = string
      principals = list(object({
        type = string
        identifiers = list(string)
      }))
      actions = list(string)
      resources = list(string)
    })), {})

    # Version configuration
    create_random_password = optional(bool, false)
    random_password_length = optional(number, 32)
    random_password_override_special = optional(string, "!@#$%^&*()_+")
    ignore_secret_changes = optional(bool, false)
    
    # Secret string configuration
    secret_string = optional(string)
    
    # Rotation configuration
    enable_rotation = optional(bool, false)
    rotation_lambda_arn = optional(string, "")
    rotation_rules = optional(map(string), {})

    # Tags
    tags = optional(map(string), {})
  })
  default = null
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
  default     = "admin" 
}

# ELK Stack Variables
variable "enable_elk_stack" {
  description = "Enable ELK Stack"
  type        = bool
  default     = true
}

variable "elk_namespace" {
  description = "Namespace for ELK Stack"
  type        = string
  default     = "monitoring"
}

variable "elasticsearch_version" {
  description = "Version of Elasticsearch Helm chart"
  type        = string
  default     = "8.5.1"
}

variable "filebeat_version" {
  description = "Version of Filebeat Helm chart"
  type        = string
  default     = "8.5.1"
}

variable "logstash_version" {
  description = "Version of Logstash Helm chart"
  type        = string
  default     = "8.5.1"
}

variable "kibana_version" {
  description = "Version of Kibana Helm chart"
  type        = string
  default     = "8.5.1"
}

variable "kibana_ingress_host" {
  description = "Hostname for Kibana ingress"
  type        = string
  default     = "kibana"
}
