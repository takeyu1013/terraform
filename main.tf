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

  private_subnet_tags = local.tag
  public_subnet_tags = merge(local.tag, {
    "kubernetes.io/role/elb" = ""
  })
}


module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets

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
        },
        {
          namespace = "kube-system"
        },
        {
          namespace = "game-2048"
        }
      ]
    }
  }
}

data "http" "albc_policy_json" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "albc" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.albc_policy_json.body
}

module "albc_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"

  create_role                   = true
  role_name                     = "aws-load-balancer-controller"
  role_policy_arns              = [aws_iam_policy.albc.arn]
  provider_url                  = module.eks.cluster_oidc_issuer_url
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = module.eks.cluster_certificate_authority_data
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

resource "helm_release" "albc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }
  set {
    name  = "serviceAccount.create"
    value = true
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.albc_irsa.iam_role_arn
  }
  set {
    name  = "region"
    value = data.aws_region.current.name
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    module.eks.fargate_profiles
  ]
}
