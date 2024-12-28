inputs = {
  vpc_name = "dev-eks-vpc"
  vpc_cidr = "10.0.0.0/16"
  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
} 