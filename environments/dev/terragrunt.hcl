include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules//eks-platform"
}

locals {
  common_config     = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  vpc_config        = read_terragrunt_config("vpc.hcl")
  eks_config        = read_terragrunt_config("eks.hcl")
  eks_addons_config = read_terragrunt_config("eks-addons.hcl")
  records_config    = read_terragrunt_config("records.hcl")
  documentdb_config = read_terragrunt_config("documentdb.hcl")
  secrets_config    = read_terragrunt_config("secrets.hcl")
}

# Merge all inputs with common config first
inputs = merge(
  local.common_config.inputs,
  local.vpc_config.inputs,
  local.eks_config.inputs,
  local.eks_addons_config.inputs,
  local.records_config.inputs,
  local.documentdb_config.inputs,
  local.secrets_config.inputs
) 