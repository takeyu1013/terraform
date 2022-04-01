output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = local.cluster_name
}

output "endpoint" {
  description = "endpoint"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cert" {
  description = "cert"
  value       = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
}
