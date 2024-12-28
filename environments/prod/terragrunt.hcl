# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the eks-platform module
terraform {
  source = "../../modules//eks-platform"
}

# Load and merge all configurations
locals {
  common_config     = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  vpc_config        = read_terragrunt_config("vpc.hcl")
  eks_config        = read_terragrunt_config("eks.hcl")
  eks_addons_config = read_terragrunt_config("eks-addons.hcl")
  records_config    = read_terragrunt_config("records.hcl")
}

# Merge all inputs with common config first
inputs = merge(
  local.common_config.inputs,
  local.vpc_config.inputs,
  local.eks_config.inputs,
  local.eks_addons_config.inputs,
  local.records_config.inputs
)

# Generate Kubernetes and Helm providers after EKS is created
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--role-arn", "arn:aws:iam::767397741479:role/TerraformRole"]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--role-arn", "arn:aws:iam::767397741479:role/TerraformRole"]
    command     = "aws"
  }
}
EOF
} 