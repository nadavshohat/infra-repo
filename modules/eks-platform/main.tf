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

  public_subnet_tags = var.public_subnet_tags
  private_subnet_tags = merge(
    var.private_subnet_tags,
    {
      "karpenter.sh/discovery" = var.cluster_name
    }
  )

  vpc_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

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

  # Fargate profile for Karpenter
  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
  }

  cluster_addons = {
    kube-proxy            = {}
    vpc-cni               = {}
  }

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${var.cluster_name}" = "owned",
      "karpenter.sh/discovery" = var.cluster_name
    }
  )
}


resource "helm_release" "kube_prometheus_stack" {
  depends_on = [module.eks]
  
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version         = "67.8.0"

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          tolerations = var.critical_node_config.tolerations
          affinity = var.critical_node_config.affinity
          retention = "30d"
          resources = {
            requests = {
              cpu = "200m"
              memory = "1Gi"
            }
            limits = {
              cpu = "500m"
              memory = "2Gi"
            }
          }
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          hosts = ["prometheus.${var.domain_name}"]
          path = "/"
          pathType = "Prefix"
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          tolerations = var.critical_node_config.tolerations
          affinity = var.critical_node_config.affinity
        }
      }
      grafana = {
        enabled = true
        adminPassword = var.grafana_admin_password
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          hosts = ["grafana.${var.domain_name}"]
          path = "/"
          pathType = "Prefix"
        }
        tolerations = var.critical_node_config.tolerations
        affinity = var.critical_node_config.affinity
        resources = {
          requests = {
            cpu = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu = "200m"
            memory = "512Mi"
          }
        }
      }
      prometheusOperator = {
        tolerations = var.critical_node_config.tolerations
        affinity = var.critical_node_config.affinity
      }
    })
  ]
}

# Karpenter Module
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name           = module.eks.cluster_name
  enable_v1_permissions  = true
  namespace             = "karpenter"

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix = false
  node_iam_role_name           = "KarpenterNodeRole-${var.cluster_name}"

  # Create instance profile
  create_instance_profile = true

  enable_irsa                    = true
  irsa_oidc_provider_arn         = module.eks.oidc_provider_arn

  # Add required policies for the node IAM role
  node_iam_role_additional_policies = {
    AmazonEKSWorkerNodePolicy      = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEKS_CNI_Policy          = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore  = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  tags = var.tags
}

# Get ECR token for Karpenter repository
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# Karpenter Helm Release
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.1.1"
  wait                = false

  values = [
    <<-EOT
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    webhook:
      enabled: false
    replicas: 1
    EOT
  ]

  depends_on = [
    module.eks,
    module.karpenter
  ]
}

# Apply Karpenter NodePool configuration
resource "kubectl_manifest" "karpenter_node_pool" {
  count = var.karpenter_node_pool_configuration.enabled ? length(var.karpenter_node_pool_configuration.manifests) : 0
  yaml_body = var.karpenter_node_pool_configuration.manifests[count.index].content
  depends_on = [
    helm_release.karpenter
  ]
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

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    configuration_values = jsonencode({
      tolerations = var.critical_node_config.tolerations
      affinity = var.critical_node_config.affinity
    })
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

  # EBS CSI Driver (Critical)
  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
      configuration_values = jsonencode({
        controller = {
          tolerations = var.critical_node_config.tolerations
          affinity = var.critical_node_config.affinity
        }
      })
    }
  }

  # NGINX Ingress Controller (Critical)
  enable_ingress_nginx = var.enable_ingress_nginx
  ingress_nginx = {
    namespace = var.ingress_nginx_namespace
    create_namespace = true
    values = [yamlencode({
      controller = {
        config = {
          "proxy-read-timeout" = "300",
          "proxy-send-timeout" = "300",
          "use-forwarded-headers" = "true"
        }
        tolerations = var.critical_node_config.tolerations
        affinity = var.critical_node_config.affinity
        service = {
          type = var.ingress_nginx_service_type,
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol" = "*"
          }
        }
        ingressClassResource = {
          name = var.ingress_class_name
          enabled = true
          default = true
          controllerValue = "k8s.io/ingress-nginx"
        }
        metrics = {
          enabled = true
          port = 10254
          service = {
            annotations = {
              "prometheus.io/scrape" = "true"
              "prometheus.io/port" = "10254"
            }
          }
          serviceMonitor = {
            enabled = true
            additionalLabels = {
              "app.kubernetes.io/name" = "ingress-nginx"
              "app.kubernetes.io/instance" = "ingress-nginx"
              "release" = "kube-prometheus-stack"
            }
            scrapeInterval = "30s"
          }
        }
      }
    })]
  }

  # Cert Manager (Critical)
  enable_cert_manager = var.enable_cert_manager
  cert_manager = {
    namespace = var.cert_manager_namespace
    create_namespace = true
    configuration_values = jsonencode({
      tolerations = var.critical_node_config.tolerations
      affinity = var.critical_node_config.affinity
    })
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

  # External Secrets Operator (Non-Critical)
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

  # ArgoCD (Non-Critical)
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
        value = "true"
      },
      {
        name  = "server.ingress.ingressClassName"
        value = "nginx"
      },
      {
        name  = "server.ingress.hosts[0]"
        value = "argocd.${var.domain_name}"
      },
      {
        name  = "server.extraArgs[0]"
        value = "--insecure"
      }
    ]
  }
}

# Wait for NGINX to be ready
resource "time_sleep" "wait_for_nginx" {
  depends_on = [module.eks_addons]
  create_duration = "60s"
}

# Wait for all addons to be ready
resource "time_sleep" "wait_for_addons" {
  depends_on = [time_sleep.wait_for_nginx]
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
        "alb.ingress.kubernetes.io/certificate-arn" = module.acm.acm_certificate_arn,
        "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]",
        "alb.ingress.kubernetes.io/scheme" = "internet-facing",
        "alb.ingress.kubernetes.io/target-type" = "ip",
        "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz",
        "alb.ingress.kubernetes.io/backend-protocol" = "HTTP",
        "alb.ingress.kubernetes.io/security-groups" = module.eks.node_security_group_id,
        "kubernetes.io/ingress.class" = "alb"
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
  create_duration = "600s"  
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

# Get ArgoCD Password
# data "kubernetes_secret" "argocd_password" {
#   metadata {
#     name      = "argocd-initial-admin-secret"
#     namespace = "argocd"
#   }
#   depends_on = [
#     module.eks_addons
#   ]
# }

# Elasticsearch
resource "helm_release" "elasticsearch" {
  count      = var.enable_elk_stack ? 1 : 0
  depends_on = [module.eks_addons]

  name       = "elasticsearch"
  repository = "elastic"
  chart      = "elasticsearch"
  namespace  = var.elk_namespace
  version    = var.elasticsearch_version
  timeout    = 900

  values = [
    yamlencode({
      replicas = 1
      minimumMasterNodes = 1
      persistence = {
        enabled = true
      }
      volumeClaimTemplate = {
        storageClassName = "gp2"
        resources = {
          requests = {
            storage = "5Gi"
          }
        }
      }
      resources = {
        requests = {
          cpu = "100m"
          memory = "512Mi"
        }
        limits = {
          cpu = "1000m"
          memory = "1Gi"
        }
      }
      tolerations = var.critical_node_config.tolerations
      affinity = var.critical_node_config.affinity
    })
  ]
}

# Filebeat
resource "helm_release" "filebeat" {
  count      = var.enable_elk_stack ? 1 : 0
  depends_on = [helm_release.elasticsearch]

  name       = "filebeat"
  repository = "elastic"
  chart      = "filebeat"
  namespace  = var.elk_namespace
  version    = var.filebeat_version

  values = [
    yamlencode({
      filebeatConfig = {
        "filebeat.yml" = <<-EOT
          filebeat.inputs:
          - type: container
            paths:
              - /var/log/containers/*.log
            processors:
            - add_kubernetes_metadata:
                host: "$${NODE_NAME}"
                matchers:
                - logs_path:
                    logs_path: "/var/log/containers/"

          output.logstash:
            hosts: ["logstash-logstash:5044"]
        EOT
      }
    })
  ]
}

# Logstash
resource "helm_release" "logstash" {
  count      = var.enable_elk_stack ? 1 : 0
  depends_on = [helm_release.elasticsearch]

  name       = "logstash"
  repository = "elastic"
  chart      = "logstash"
  namespace  = var.elk_namespace
  version    = var.logstash_version

  values = [
    yamlencode({
      tolerations = var.critical_node_config.tolerations
      affinity = var.critical_node_config.affinity
      extraEnvs = [
        {
          name = "ELASTICSEARCH_USERNAME"
          valueFrom = {
            secretKeyRef = {
              name = "elasticsearch-master-credentials"
              key = "username"
            }
          }
        },
        {
          name = "ELASTICSEARCH_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = "elasticsearch-master-credentials"
              key = "password"
            }
          }
        }
      ]
      logstashPipeline = {
        "logstash.conf" = <<-EOT
          input {
            beats {
              port => 5044
            }
          }

          output {
            elasticsearch {
              hosts => "https://elasticsearch-master:9200"
              cacert => "/usr/share/logstash/config/elasticsearch-master-certs/ca.crt"
              user => "$${ELASTICSEARCH_USERNAME}"
              password => "$${ELASTICSEARCH_PASSWORD}"
            }
          }
        EOT
      }
      secretMounts = [
        {
          name = "elasticsearch-master-certs"
          secretName = "elasticsearch-master-certs"
          path = "/usr/share/logstash/config/elasticsearch-master-certs"
        }
      ]
      service = {
        type = "ClusterIP"
        ports = [
          {
            name = "beats"
            port = 5044
            protocol = "TCP"
            targetPort = 5044
          },
          {
            name = "http"
            port = 8080
            protocol = "TCP"
            targetPort = 8080
          }
        ]
      }
    })
  ]
}

# Kibana
resource "helm_release" "kibana" {
  count      = var.enable_elk_stack ? 1 : 0
  depends_on = [helm_release.elasticsearch]

  name       = "kibana"
  repository = "elastic"
  chart      = "kibana"
  namespace  = var.elk_namespace
  version    = var.kibana_version

  values = [
    yamlencode({
      ingress = {
        enabled = true
        ingressClassName = "nginx"
        hosts = ["${var.kibana_ingress_host}.${var.domain_name}"]
        path = "/"
        pathType = "Prefix"
      }
      tolerations = var.critical_node_config.tolerations
      affinity = var.critical_node_config.affinity
    })
  ]
}



# Add inbound rules to node security group for ALB
resource "aws_security_group_rule" "node_ingress_alb_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  cidr_blocks              = ["0.0.0.0/0"]
  description             = "Allow ALB to access pod HTTP"
}

resource "aws_security_group_rule" "node_ingress_alb_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  cidr_blocks              = ["0.0.0.0/0"]
  description             = "Allow ALB to access pod HTTPS"
}

