inputs = {
  cluster_name = "dev-eks-cluster"

  eks_managed_node_groups = {
    general = {
      name = "general"
      instance_types = ["t3.medium"]
      min_size     = 1
      max_size     = 3
      desired_size = 2
      
      labels = {
        role = "general"
      }
      
      taints = []
    }
  }

  tags = {
    Environment = "dev"
  }
} 