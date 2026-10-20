# ============================================================================
# AWS VARIABLES
# ============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile; null uses the standard AWS credential chain"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "boomi-elastic"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "boomi-elastic"
    ManagedBy = "terraform"
  }
}

# ============================================================================
# VPC VARIABLES
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "NAT is required for private nodes in this configuration"
  type        = bool
  default     = true
  validation {
    condition     = var.enable_nat_gateway
    error_message = "Private nodes require NAT; no alternative egress is provisioned."
  }
}

variable "enable_vpn_gateway" {
  description = "Enable VPN Gateway"
  type        = bool
  default     = false
}

# ============================================================================
# EKS CLUSTER VARIABLES
# ============================================================================

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "boomi-elastic-cluster"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.eks_cluster_version))
    error_message = "Choose an EKS version available in your region and supported by Boomi."
  }
}

variable "eks_cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "eks_cluster_log_retention_days" {
  description = "Number of days to retain EKS cluster logs"
  type        = number
  default     = 7
}

# ============================================================================
# EKS NODE GROUP VARIABLES
# ============================================================================

variable "system_node_group_config" {
  description = "Configuration for system node group"
  type = object({
    name           = string
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
  })
  default = {
    name           = "system-nodes"
    instance_types = ["t3.large"]
    desired_size   = 2
    min_size       = 2
    max_size       = 4
    disk_size      = 50
  }
}

variable "boomi_node_group_config" {
  description = "Configuration for Boomi cloud node group"
  type = object({
    name           = string
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
  })
  default = {
    name           = "boomi-cloud-nodes"
    instance_types = ["t3.xlarge"]
    desired_size   = 3
    min_size       = 3
    max_size       = 6
    disk_size      = 100
  }
}

# ============================================================================
# BOOMI CONFIGURATION VARIABLES
# ============================================================================

variable "boomi_install_token" {
  description = "Boomi install token (from Cloud Management > Install Cloud Molecule)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.boomi_install_token) > 0
    error_message = "Boomi install token is required."
  }
}

variable "boomi_cloud_name" {
  description = "Name of the Boomi Cloud in the platform"
  type        = string
  default     = "ElasticCloud"
}

variable "boomi_atom_name" {
  description = "Atom name for the cloud molecule"
  type        = string
  default     = "ElasticCloud"
}

variable "boomi_runtime_cloud_image_tag" {
  description = "Docker image tag for Boomi runtime cloud"
  type        = string
  default     = "5.1.1"
}

variable "boomi_runtime_cloud_replicas" {
  description = "Number of runtime cloud pod replicas"
  type        = number
  default     = 3
  validation {
    condition     = var.boomi_runtime_cloud_replicas >= 1
    error_message = "Runtime cloud replicas must be at least 1."
  }
}

variable "boomi_elastic_controller_image_tag" {
  description = "Docker image tag for Boomi elastic controller"
  type        = string
  default     = "0.1.32"
}

variable "boomi_elastic_controller_replicas" {
  description = "Number of elastic controller pod replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.boomi_elastic_controller_replicas >= 1
    error_message = "Elastic controller replicas must be at least 1."
  }
}

# ============================================================================
# BOOMI WORKER CONFIGURATION
# ============================================================================

variable "boomi_max_workers" {
  description = "Maximum number of worker pods per attachment"
  type        = number
  default     = 10
}

variable "boomi_min_workers" {
  description = "Minimum number of worker pods per attachment (0 = scale to zero)"
  type        = number
  default     = 1
}

variable "boomi_max_running_executions" {
  description = "Maximum running executions per worker pod"
  type        = number
  default     = 10
}

variable "boomi_elastic_scaling_threshold" {
  description = "Percentage of max executions to trigger scaling (0-100)"
  type        = number
  default     = 80
  validation {
    condition     = var.boomi_elastic_scaling_threshold > 0 && var.boomi_elastic_scaling_threshold <= 100
    error_message = "Elastic scaling threshold must be between 1 and 100."
  }
}

variable "boomi_runner_cpu_request" {
  description = "CPU request for forked execution runner pods"
  type        = string
  default     = "500m"
}

variable "boomi_runner_memory_request" {
  description = "Memory request for forked execution runner pods"
  type        = string
  default     = "512Mi"
}

variable "boomi_worker_cpu_request" {
  description = "CPU request for worker pods"
  type        = string
  default     = "1000m"
}

variable "boomi_worker_memory_request" {
  description = "Memory request for worker pods"
  type        = string
  default     = "700Mi"
}

# ============================================================================
# KUBERNETES NAMESPACE VARIABLES
# ============================================================================

variable "boomi_namespace" {
  description = "Kubernetes namespace for Boomi components"
  type        = string
  default     = "boomi"
}

variable "keda_namespace" {
  description = "Kubernetes namespace for KEDA"
  type        = string
  default     = "keda"
}

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring components"
  type        = string
  default     = "monitoring"
}

# ============================================================================
# STORAGE VARIABLES
# ============================================================================

variable "enable_efs" {
  description = "Shared EFS storage is required for the runtime cloud"
  type        = bool
  default     = true
  validation {
    condition     = var.enable_efs
    error_message = "This runtime cloud requires shared ReadWriteMany EFS storage."
  }
}

variable "efs_performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be generalPurpose or maxIO."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode (bursting or provisioned)"
  type        = string
  default     = "bursting"
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be bursting or provisioned."
  }
}

variable "efs_provisioned_throughput_mibps" {
  description = "Provisioned throughput for EFS in MiB/s (only if throughput_mode = provisioned)"
  type        = number
  default     = 100
}

variable "runtime_storage_size" {
  description = "Size of the persistent volume claim for runtime"
  type        = string
  default     = "100Gi"
}

# ============================================================================
# HELM CHART VARIABLES
# ============================================================================

variable "helm_keda_version" {
  description = "Helm chart version for KEDA"
  type        = string
  default     = "2.13.0"
}

variable "helm_boomi_runtime_cloud_version" {
  description = "Helm chart version for Boomi runtime cloud"
  type        = string
  default     = "0.1.0"
}

variable "helm_boomi_elastic_controller_version" {
  description = "Helm chart version for Boomi elastic controller"
  type        = string
  default     = "0.1.0"
}

variable "helm_prometheus_version" {
  description = "Helm chart version for kube-prometheus-stack"
  type        = string
  default     = "54.0.0"
}

# ============================================================================
# MONITORING VARIABLES
# ============================================================================

variable "enable_monitoring" {
  description = "Enable Prometheus and Grafana monitoring stack"
  type        = bool
  default     = true
}

variable "prometheus_retention_days" {
  description = "Number of days to retain Prometheus metrics"
  type        = number
  default     = 15
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "prom-operator"
}

# ============================================================================
# CLUSTER AUTOSCALER VARIABLES
# ============================================================================

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler for automatic node scaling"
  type        = bool
  default     = true
}

variable "cluster_autoscaler_version" {
  description = "Version of Cluster Autoscaler to deploy"
  type        = string
  # Match the minor version of eks_cluster_version.

}

# ============================================================================
# AWS LOAD BALANCER CONTROLLER VARIABLES
# ============================================================================

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller for ALB ingress"
  type        = bool
  default     = true
}

# ============================================================================
# ENCRYPTION VARIABLES
# ============================================================================

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for EKS secrets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  validation {
    condition     = var.kms_key_deletion_window_days >= 7 && var.kms_key_deletion_window_days <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# ============================================================================
# LOGGING VARIABLES
# ============================================================================

variable "enable_log_forwarding" {
  description = "Enable forwarding of container logs to CloudWatch"
  type        = bool
  default     = false
}

variable "cloudwatch_log_group" {
  description = "CloudWatch log group name for container logs"
  type        = string
  default     = "/aws/eks/boomi-elastic"
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30
}

