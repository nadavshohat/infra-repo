inputs = {
  cluster_name = "dev-eks-cluster"
  cluster_version = "1.27"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  enable_cluster_creator_admin_permissions = true

  # Add Karpenter NodePool configuration to be applied
  karpenter_node_pool_configuration = {
    enabled = true
    manifests = [
      {
        content = file("../../karpenter-nodepool-critical.yaml")
      },
      {
        content = file("../../karpenter-nodepool-default.yaml")
      },
      {
        content = file("../../karpenter-ec2nodeclass.yaml")
      }
    ]
  }

  tags = {
    Environment = "dev"
  }
} 