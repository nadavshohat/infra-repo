inputs = {
  cluster_name = "prod-eks-cluster"

  eks_managed_node_groups = {
    general = {
      name = "general"
      instance_types = ["t3.large"]
      min_size     = 2
      max_size     = 5
      desired_size = 3
      
      labels = {
        role = "general"
      }
      
      taints = []
    }
  }

  tags = {
    Environment = "prod"
  }
} 