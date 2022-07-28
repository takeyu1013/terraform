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
    cluster_egress_internet = {
      description      = "Allow cluster egress access to the Internet."
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  node_security_group_additional_rules = {
    workers_ingress_cluster = {
      description                   = "Allow workers pods to receive communication from the cluster control plane."
      protocol                      = "tcp"
      from_port                     = 1025
      to_port                       = 65535
      type                          = "ingress"
      source_cluster_security_group = true
    }
    workers_ingress_self = {
      description = "Allow node to communicate with each other."
      protocol    = "-1"
      from_port   = 0
      to_port     = 65535
      type        = "ingress"
      self        = true
    }
    workers_egress_internet = {
      description      = "Allow nodes all egress to the Internet."
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
}
