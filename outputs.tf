# ============================================================================
# AWS INFRASTRUCTURE OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# VPC OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

# ============================================================================
# EKS CLUSTER OUTPUTS
# ============================================================================

output "eks_cluster_id" {
  description = "EKS Cluster ID"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_version" {
  description = "EKS Cluster Kubernetes Version"
  value       = aws_eks_cluster.main.version
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_arn" {
  description = "EKS Cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_certificate_authority" {
  description = "EKS Cluster CA certificate (base64 encoded)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# ============================================================================
# EKS NODE GROUPS OUTPUTS
# ============================================================================

output "system_node_group_id" {
  description = "System Node Group ID"
  value       = aws_eks_node_group.system.id
}

output "system_node_group_status" {
  description = "System Node Group Status"
  value       = aws_eks_node_group.system.status
}

output "boomi_node_group_id" {
  description = "Boomi Node Group ID"
  value       = aws_eks_node_group.boomi_cloud.id
}

output "boomi_node_group_status" {
  description = "Boomi Node Group Status"
  value       = aws_eks_node_group.boomi_cloud.status
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "eks_cluster_role_arn" {
  description = "EKS Cluster IAM Role ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "EKS Node IAM Role ARN"
  value       = aws_iam_role.eks_node.arn
}

output "ebs_csi_driver_role_arn" {
  description = "EBS CSI Driver IAM Role ARN"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "efs_csi_driver_role_arn" {
  description = "EFS CSI Driver IAM Role ARN"
  value       = var.enable_efs ? aws_iam_role.efs_csi_driver[0].arn : null
}

output "keda_role_arn" {
  description = "KEDA IAM Role ARN"
  value       = aws_iam_role.keda.arn
}

output "boomi_workload_role_arn" {
  description = "Boomi Workload IAM Role ARN"
  value       = aws_iam_role.boomi_workload.arn
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IAM Role ARN"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "aws_load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = var.enable_aws_load_balancer_controller ? aws_iam_role.aws_load_balancer_controller[0].arn : null
}

# ============================================================================
# KUBERNETES OUTPUTS
# ============================================================================

output "kubernetes_cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.main.name
}

output "kubernetes_config" {
  description = "Kubernetes Config (generate with: aws eks update-kubeconfig)"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "boomi_namespace" {
  description = "Boomi Namespace"
  value       = kubernetes_namespace.boomi.metadata[0].name
}

output "keda_namespace" {
  description = "KEDA Namespace"
  value       = kubernetes_namespace.keda.metadata[0].name
}

output "monitoring_namespace" {
  description = "Monitoring Namespace"
  value       = var.enable_monitoring ? kubernetes_namespace.monitoring[0].metadata[0].name : null
}

output "boomi_service_account" {
  description = "Boomi Workload Service Account"
  value       = kubernetes_service_account.boomi_workload.metadata[0].name
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "efs_file_system_id" {
  description = "EFS File System ID"
  value       = var.enable_efs ? aws_efs_file_system.runtime[0].id : null
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = var.enable_efs ? aws_efs_file_system.runtime[0].dns_name : null
}

output "efs_access_point_id" {
  description = "EFS Access Point ID for Boomi runtime"
  value       = var.enable_efs ? aws_efs_access_point.runtime[0].id : null
}

output "runtime_pvc_name" {
  description = "Kubernetes PVC name for Boomi runtime"
  value       = "runtime-claim"
}

output "runtime_storage_class" {
  description = "Kubernetes Storage Class for Boomi runtime"
  value       = var.enable_efs ? "efs-sc" : "ebs-gp3"
}

# ============================================================================
# HELM RELEASES OUTPUTS
# ============================================================================

output "keda_helm_release_name" {
  description = "KEDA Helm Release Name"
  value       = helm_release.keda.id
}

output "boomi_elastic_controller_helm_release_name" {
  description = "Boomi Elastic Controller Helm Release Name"
  value       = helm_release.boomi_elastic_controller.id
}

output "boomi_runtime_cloud_helm_release_name" {
  description = "Boomi Runtime Cloud Helm Release Name"
  value       = helm_release.boomi_runtime_cloud.id
}

output "monitoring_helm_release_name" {
  description = "Monitoring Stack Helm Release Name"
  value       = var.enable_monitoring ? helm_release.kube_prometheus_stack[0].id : null
}

output "cluster_autoscaler_helm_release_name" {
  description = "Cluster Autoscaler Helm Release Name"
  value       = var.enable_cluster_autoscaler ? helm_release.cluster_autoscaler[0].id : null
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "grafana_access_command" {
  description = "Command to access Grafana dashboard"
  value = var.enable_monitoring ? "kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/monitoring-grafana 3000:80" : null
}

output "grafana_url" {
  description = "Grafana URL (after port-forward)"
  value       = var.enable_monitoring ? "http://localhost:3000" : null
}

output "grafana_credentials" {
  description = "Grafana login credentials"
  value = var.enable_monitoring ? {
    username = "admin"
    password = "Use the grafana_admin_password variable"
  } : null
  sensitive = true
}

output "prometheus_access_command" {
  description = "Command to access Prometheus dashboard"
  value = var.enable_monitoring ? "kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/monitoring-kube-prometheus-prometheus 9090:9090" : null
}

output "prometheus_url" {
  description = "Prometheus URL (after port-forward)"
  value       = var.enable_monitoring ? "http://localhost:9090" : null
}

# ============================================================================
# LOGGING OUTPUTS
# ============================================================================

output "eks_cluster_logs_group" {
  description = "CloudWatch Log Group for EKS Cluster Logs"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

# ============================================================================
# USEFUL COMMANDS
# ============================================================================

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "verify_cluster_command" {
  description = "Command to verify cluster is working"
  value       = "kubectl get nodes -o wide"
}

output "check_keda_command" {
  description = "Command to check KEDA installation"
  value       = "kubectl get pods -n ${kubernetes_namespace.keda.metadata[0].name}"
}

output "check_boomi_command" {
  description = "Command to check Boomi installation"
  value       = "kubectl get pods -n ${kubernetes_namespace.boomi.metadata[0].name}"
}

output "check_pvc_command" {
  description = "Command to check Boomi runtime PVC"
  value       = "kubectl get pvc -n ${kubernetes_namespace.boomi.metadata[0].name}"
}

output "view_boomi_logs_command" {
  description = "Command to view Boomi runtime cloud logs"
  value       = "kubectl logs -n ${kubernetes_namespace.boomi.metadata[0].name} -l app=runtime-cloud -f"
}

# ============================================================================
# IMPORTANT NOTES
# ============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value = join("\n", [
    "1. Configure kubectl: aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}",
    "2. Verify cluster: kubectl get nodes",
    "3. Check Boomi: kubectl get pods -n ${kubernetes_namespace.boomi.metadata[0].name}",
    "4. Check Boomi Platform: Manage > Runtime Management > Verify ElasticCloud is Online",
    "5. Create Environment and Attachment in Boomi Platform for testing",
    "6. Enable Execution Workers in the cloud properties",
    "7. Set Attachment Quotas for worker configuration",
    "8. Deploy test process to verify elastic execution"
  ])
}

output "destruction_warning" {
  description = "Warning before destroying infrastructure"
  value = join("\n", [
    "⚠️  WARNING: Destroying this infrastructure will:",
    "- Delete the EKS cluster and all running workloads",
    "- Delete the VPC and all networking resources",
    "- Delete the EFS file system (if not backed up)",
    "- Make the Boomi cloud unavailable",
    "",
    "Ensure you have backups of critical data before running terraform destroy"
  ])
}
