project_name = ""
environment  = "dev"
aws_region   = ""
owner        = ""

vpc_cidr           = ""
availability_zones = [""]

public_subnet_cidrs  = [""]
private_subnet_cidrs = [""]

cluster_public_access_cidrs = [
  
]

access_entries = {
  admin = {
    principal_arn = ""
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
}
