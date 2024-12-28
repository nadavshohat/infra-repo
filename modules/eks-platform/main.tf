terraform {
  backend "s3" {}
}

# Data source for AWS Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}


# VPC locals
locals {
  # Get all available AZs
  azs = data.aws_availability_zones.available.names

  # Get subnet bits with default fallback
  newbits = var.subnet_bits != null ? var.subnet_bits : 8
  
  # Calculate subnet ranges
  public_subnets = {
    for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, local.newbits, i + 1)
  }

  private_subnets = {
    for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, local.newbits, i + length(local.azs) + 1)
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for subnet in values(local.private_subnets) : subnet]
  public_subnets  = [for subnet in values(local.public_subnets) : subnet]

  enable_nat_gateway     = var.enable_nat_gateway
  enable_vpn_gateway     = var.enable_vpn_gateway
  enable_dns_hostnames   = var.enable_dns_hostnames
  enable_dns_support     = var.enable_dns_support
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  tags = var.tags
}

# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Enable both private and public access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  vpc_id     = module.vpc.vpc_id
  subnet_ids = slice(module.vpc.private_subnets, 0, 3)

  # Node group defaults
  eks_managed_node_group_defaults = {
    create_iam_role = true
    iam_role_attach_cni_policy = true
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  eks_managed_node_groups = var.eks_managed_node_groups

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# Wait for EKS cluster to be ready
resource "time_sleep" "wait_for_eks" {
  depends_on = [module.eks]
  create_duration = "30s"
}

# AWS Load Balancer Controller
module "aws_load_balancer_controller" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.19.0"

  depends_on = [time_sleep.wait_for_eks]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Only install AWS Load Balancer Controller
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "region"
        value = var.aws_region
      }
    ]
  }
}

# Wait for AWS Load Balancer Controller to be ready
resource "time_sleep" "wait_for_alb" {
  depends_on = [module.aws_load_balancer_controller]
  create_duration = "60s"
}

# Other EKS Addons
module "eks_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.19.0"

  depends_on = [
    time_sleep.wait_for_alb  
  ]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Enable NGINX Ingress Controller
  enable_ingress_nginx = var.enable_ingress_nginx
  ingress_nginx = {
    namespace = var.ingress_nginx_namespace
    create_namespace = true
    values = [yamlencode({
      controller = {
        service = {
          type = var.ingress_nginx_service_type
        }
        ingressClassResource = {
          name = var.ingress_class_name
          enabled = true
          default = true
          controllerValue = "k8s.io/ingress-nginx"
        }
      }
    })]
  }

  # Enable Cert Manager
  enable_cert_manager = var.enable_cert_manager
  cert_manager = {
    namespace = var.cert_manager_namespace
    create_namespace = true
    set = [
      {
        name  = "serviceAccount.name"
        value = var.cert_manager_service_account
      },
      {
        name  = "installCRDs"
        value = "true"
      }
    ]
  }

  # Enable External Secrets Operator
  enable_external_secrets = var.enable_external_secrets
  external_secrets = {
    namespace = var.external_secrets_namespace
    set = [
      {
        name  = "serviceAccount.name"
        value = var.external_secrets_service_account
      }
    ]
  }

  # Configure External Secrets permissions
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"]
  external_secrets_ssm_parameter_arns   = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/*"]

  # Enable ArgoCD
  enable_argocd = var.enable_argocd
  argocd = {
    namespace = var.argocd_namespace
    chart_version = var.argocd_helm_version
    set = [
      {
        name  = "server.service.type"
        value = var.argocd_service_type
      },
      {
        name  = "server.ingress.enabled"
        value = "false"
      },
      {
        name  = "server.extraArgs[0]"
        value = "--insecure"
      },
      {
        name  = "server.certificate.enabled"
        value = "false"
      }
    ]
  }
}

# Wait for all addons to be ready
resource "time_sleep" "wait_for_addons" {
  depends_on = [module.eks_addons]
  create_duration = "30s"
}

# Create the ALB Ingress for NGINX Controller
resource "kubernetes_ingress_v1" "nginx_alb" {
  count = try(var.ingress_alb.enabled, true) ? 1 : 0

  depends_on = [
    time_sleep.wait_for_addons,
    module.aws_load_balancer_controller,
    time_sleep.wait_for_alb,
    module.acm
  ]

  metadata {
    name      = try(var.ingress_alb.name, "nginx-alb")
    namespace = try(var.ingress_alb.namespace, "ingress-nginx")
    annotations = merge(
      try(var.ingress_alb.annotations, {}),
      {
        "alb.ingress.kubernetes.io/certificate-arn" = module.acm.acm_certificate_arn
      }
    )
  }

  spec {
    rule {
      http {
        path {
          path = try(var.ingress_alb.path, "/*")
          backend {
            service {
              name = try(var.ingress_alb.service.name, "ingress-nginx-controller")
              port {
                number = try(var.ingress_alb.service.port, 80)
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = false
  }
}


# Wait for ALB to be ready
resource "time_sleep" "wait_for_alb_ready" {
  depends_on = [kubernetes_ingress_v1.nginx_alb]
  create_duration = "300s"  
}

# Route53 Records Module
module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 2.0"

  depends_on = [time_sleep.wait_for_alb_ready]

  zone_name = var.zone_name
  records = [
    for name, record in var.route53_records : {
      name    = record.name
      type    = record.type
      ttl     = record.ttl
      records = [try(kubernetes_ingress_v1.nginx_alb[0].status[0].load_balancer[0].ingress[0].hostname, "")]
      allow_overwrite = true  
    }
  ]
}

# Create ACM Certificate
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.0"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  zone_id                   = data.aws_route53_zone.selected.zone_id
  validation_method         = var.validation_method
  wait_for_validation      = var.wait_for_validation

  tags = merge(
    {
      Name = var.domain_name
    },
    var.tags
  )
}

# Get Route53 zone data
data "aws_route53_zone" "selected" {
  name = var.zone_name
}

# Get ArgoCD Password
data "kubernetes_secret" "argocd_password" {
  depends_on = [module.eks_addons, time_sleep.wait_for_addons]
  
  metadata {
    name = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }
}

# Create DocumentDB Cluster
module "documentdb_cluster" {
  source  = "cloudposse/documentdb-cluster/aws"
  version = "0.27.0"

  enabled = var.documentdb.enabled
  name      = "microstore"
  stage     = var.environment
  namespace = "app"

  cluster_size     = var.documentdb.cluster_size
  instance_class   = var.documentdb.instance_class
  engine_version   = var.documentdb.engine_version
  master_username  = var.documentdb.master_username

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  allowed_security_groups = [module.eks.node_security_group_id]

  storage_encrypted = var.documentdb.storage_encrypted
  retention_period = var.documentdb.retention_period

  skip_final_snapshot     = var.documentdb.skip_final_snapshot
  deletion_protection     = var.documentdb.deletion_protection
  preferred_backup_window = var.documentdb.preferred_backup_window
  preferred_maintenance_window = var.documentdb.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = var.documentdb.enabled_cloudwatch_logs_exports

  cluster_parameters = [
    {
      apply_method = "pending-reboot"
      name         = "tls"
      value        = "disabled"
    }
  ]
  cluster_family = "docdb4.0"

  tags = var.documentdb.tags
}

# Create DocumentDB secrets using AWS Secrets Manager
module "documentdb_secrets" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "1.3.1"
  count   = var.documentdb.enabled && var.secrets_manager.enabled ? 1 : 0

  name                   = var.secrets_manager.name_prefix
  description            = var.secrets_manager.description
  recovery_window_in_days = var.secrets_manager.recovery_window_in_days

  # Policy configuration
  create_policy       = var.secrets_manager.create_policy
  block_public_policy = var.secrets_manager.block_public_policy
  policy_statements   = merge(
    var.secrets_manager.policy_statements,
    {
      external_secrets = {
        sid = "AllowExternalSecretsOperator"
        principals = [{
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          ]
        }]
        actions = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        resources = ["*"]
      }
    }
  )

  # Secret string with DocumentDB credentials
  secret_string = jsonencode({
    username = module.documentdb_cluster.master_username
    password = module.documentdb_cluster.master_password
    host     = module.documentdb_cluster.endpoint
  })

  # Version configuration
  ignore_secret_changes = var.secrets_manager.ignore_secret_changes
  create_random_password = var.secrets_manager.create_random_password
  random_password_length = var.secrets_manager.random_password_length
  random_password_override_special = var.secrets_manager.random_password_override_special

  # Rotation configuration
  enable_rotation     = var.secrets_manager.enable_rotation
  rotation_lambda_arn = var.secrets_manager.rotation_lambda_arn
  rotation_rules      = var.secrets_manager.rotation_rules

  tags = merge(
    var.secrets_manager.tags,
    var.tags,
    {
      Environment = var.environment
      Service     = "documentdb"
    }
  )
}



