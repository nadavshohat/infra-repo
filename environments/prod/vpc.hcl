inputs = {
  vpc_name = "prod-eks-vpc"
  vpc_cidr = "10.1.0.0/16"
  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true
} 