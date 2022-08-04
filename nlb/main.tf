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
  source = "terraform-aws-modules/eks/aws"

  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets

  eks_managed_node_groups = { default = {} }
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

  cluster_security_group_additional_rules = {
    cluster_egress_node = {
      description                = "NGINX Admission Hook"
      protocol                   = "tcp"
      from_port                  = 8443
      to_port                    = 8443
      type                       = "egress"
      source_node_security_group = true
    }
  }
  node_security_group_additional_rules = {
    node_ingress_cluster = {
      description                   = "NGINX Admission Hook"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}

resource "aws_security_group_rule" "node_egress_cluster_primary" {
  security_group_id        = module.eks.node_security_group_id
  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_primary_security_group_id
}

resource "aws_security_group_rule" "cluster_primary_ingress_node" {
  security_group_id        = module.eks.cluster_primary_security_group_id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
}

