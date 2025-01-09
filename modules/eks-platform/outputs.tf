# VPC Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_cidrs" {
  description = "List of cidr blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "public_subnet_cidrs" {
  description = "List of cidr blocks of public subnets"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = module.vpc.natgw_ids
}

output "availability_zones" {
  description = "List of availability zones used in the VPC"
  value       = module.vpc.azs
}

# EKS Outputs
output "cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_version" {
  description = "The Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_connect" {
  description = "Command to configure kubectl"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${var.cluster_name} --role-arn ${var.aws_role_arn}"
}

# EKS Addons Outputs
output "alb_controller_iam_role_arn" {
  description = "ARN of IAM role for AWS Load Balancer Controller"
  value       = try(module.aws_load_balancer_controller.aws_load_balancer_controller.iam_role_arn, "")
}

output "external_secrets_iam_role_arn" {
  description = "ARN of IAM role for External Secrets Operator"
  value       = try(module.eks_addons.external_secrets.iam_role_arn, "")
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = try(module.eks_addons.argocd.namespace, "")
}

output "ingress_nginx_namespace" {
  description = "Namespace where NGINX Ingress Controller is installed"
  value       = try(module.eks_addons.ingress_nginx.namespace, "")
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = try(kubernetes_ingress_v1.nginx_alb[0].status[0].load_balancer[0].ingress[0].hostname, "")
}

# Route53 Records Outputs
output "route53_record_fqdn" {
  description = "The FQDN of the Route53 record"
  value       = module.records.route53_record_fqdn
}

output "route53_record_name" {
  description = "The name of the Route53 record"
  value       = module.records.route53_record_name
}

# output "argocd_admin_password" {
#   description = "ArgoCD initial admin password"
#   value       = data.kubernetes_secret.argocd_password.data.password
#   sensitive   = true
# }

output "alb_hostname" {
  description = "ALB hostname for the NGINX ingress controller"
  value       = try(kubernetes_ingress_v1.nginx_alb[0].status[0].load_balancer[0].ingress[0].hostname, "")
}

# ACM Outputs
output "acm_certificate_arn" {
  description = "The ARN of the certificate"
  value       = module.acm.acm_certificate_arn
}

output "acm_certificate_domain_validation_options" {
  description = "A list of attributes to feed into other resources to complete certificate validation"
  value       = module.acm.acm_certificate_domain_validation_options
}

# DocumentDB Outputs
output "documentdb_cluster_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = try(module.documentdb_cluster.endpoint, null)
}

output "documentdb_reader_endpoint" {
  description = "DocumentDB cluster reader endpoint"
  value       = try(module.documentdb_cluster.reader_endpoint, null)
}

output "documentdb_cluster_name" {
  description = "DocumentDB cluster identifier"
  value       = try(module.documentdb_cluster.cluster_name, null)
}

output "documentdb_master_username" {
  description = "DocumentDB master username"
  value       = try(module.documentdb_cluster.master_username, null)
  sensitive   = true
}

output "documentdb_security_group_id" {
  description = "ID of the DocumentDB security group"
  value       = try(module.documentdb_cluster.security_group_id, null)
}
