data "aws_region" "current" {}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "cluster"
  tag = {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name               = "vpc"
  cidr               = "10.0.0.0/16"
  azs                = data.aws_availability_zones.available.names
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_tags = merge(local.tag, {
    "kubernetes.io/role/internal-elb" = ""
  })
  public_subnet_tags = merge(local.tag, {
    "kubernetes.io/role/elb" = ""
  })
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.24.0"

  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnets      = module.vpc.private_subnets

  node_groups = { default = {} }
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        },
        {
          namespace = "default"
          labels = {
            WorkerType = "fargate"
          }
        },
      ]
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "auth" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token
}

