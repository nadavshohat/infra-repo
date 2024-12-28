inputs = {
  # Common AWS settings
  aws_region = "us-east-1"
  aws_role_arn = "arn:aws:iam::767397741479:role/TerraformRole"

  # Common VPC settings
  enable_dns_hostnames = true
  enable_dns_support = true
  enable_vpn_gateway = false
  subnet_bits = 8

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  # Common EKS settings
  cluster_version = "1.31"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  enable_cluster_creator_admin_permissions = true

  # Common Addons Configuration
  enable_aws_load_balancer_controller = true

  # NGINX Ingress Controller
  enable_ingress_nginx = true
  ingress_nginx_namespace = "ingress-nginx"
  ingress_nginx_service_type = "NodePort"
  ingress_class_name = "nginx"

  # Cert Manager
  enable_cert_manager = true
  cert_manager_namespace = "cert-manager"
  cert_manager_service_account = "cert-manager"

  # External Secrets
  enable_external_secrets = true
  external_secrets_namespace = "external-secrets"
  external_secrets_service_account = "external-secrets"

  # ArgoCD
  enable_argocd = true
  argocd_namespace = "argocd"
  argocd_helm_version = "5.46.7"
  argocd_service_type = "ClusterIP"

  # Shared ALB Ingress Configuration base settings
  ingress_alb = {
    name = "nginx-alb"
    namespace = "ingress-nginx"
    service = {
      name = "ingress-nginx-controller"
      port = 80
    }
    path = "/*"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/group.name"       = "shared"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-policy"       = "ELBSecurityPolicy-TLS-1-2-2017-01"
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/conditions.ssl-redirect" = "[{\"Field\":\"http-header\",\"HttpHeaderConfig\":{\"HttpHeaderName\": \"X-Forwarded-Proto\",\"Values\":[\"http\"]}}]"
    }
  }

  # Common tags
  tags = {
    Terraform = "true"
  }
} 