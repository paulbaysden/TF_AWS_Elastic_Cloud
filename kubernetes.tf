# ============================================================================
# KUBERNETES NAMESPACES
# ============================================================================

resource "kubernetes_namespace" "boomi" {
  metadata {
    name = var.boomi_namespace
    labels = {
      "app.kubernetes.io/name"       = "boomi"
      "app.kubernetes.io/part-of"    = "boomi-elastic"
      "kubernetes.io/metadata.name"  = var.boomi_namespace
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_namespace" "keda" {
  metadata {
    name = var.keda_namespace
    labels = {
      "app.kubernetes.io/name"       = "keda"
      "app.kubernetes.io/part-of"    = "boomi-elastic"
      "kubernetes.io/metadata.name"  = var.keda_namespace
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name = var.monitoring_namespace
    labels = {
      "app.kubernetes.io/name"       = "monitoring"
      "app.kubernetes.io/part-of"    = "boomi-elastic"
      "kubernetes.io/metadata.name"  = var.monitoring_namespace
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# ============================================================================
# SERVICE ACCOUNTS WITH IRSA
# ============================================================================

# Boomi Workload Service Account
resource "kubernetes_service_account" "boomi_workload" {
  metadata {
    name      = "boomi-workload-sa"
    namespace = kubernetes_namespace.boomi.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.boomi_workload.arn
    }
  }

  depends_on = [kubernetes_namespace.boomi]
}

# KEDA Service Account (with IRSA if custom metrics from AWS)
resource "kubernetes_service_account" "keda" {
  metadata {
    name      = "keda-operator"
    namespace = kubernetes_namespace.keda.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.keda.arn
    }
  }

  depends_on = [kubernetes_namespace.keda]
}

# ============================================================================
# RBAC - CLUSTER ROLES
# ============================================================================

# Allow Boomi workloads to read pods and service metadata
resource "kubernetes_cluster_role" "boomi_workload" {
  metadata {
    name = "boomi-workload"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/logs"]
    verbs      = ["get"]
  }

  depends_on = [kubernetes_namespace.boomi]
}

# Cluster role for reading metrics (for monitoring/scaling)
resource "kubernetes_cluster_role" "metrics_reader" {
  metadata {
    name = "metrics-reader"
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list"]
  }
}

# ============================================================================
# RBAC - CLUSTER ROLE BINDINGS
# ============================================================================

resource "kubernetes_cluster_role_binding" "boomi_workload" {
  metadata {
    name = "boomi-workload"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.boomi_workload.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.boomi_workload.metadata[0].name
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.boomi_workload]
}

# ============================================================================
# RBAC - ROLE (Namespace-scoped)
# ============================================================================

# Boomi namespace role for managing resources within the namespace
resource "kubernetes_role" "boomi_manager" {
  metadata {
    name      = "boomi-manager"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/logs", "pods/exec", "pods/attach"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# RBAC - ROLE BINDINGS (Namespace-scoped)
# ============================================================================

resource "kubernetes_role_binding" "boomi_manager" {
  metadata {
    name      = "boomi-manager"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.boomi_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.boomi_workload.metadata[0].name
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  depends_on = [kubernetes_role.boomi_manager]
}

# ============================================================================
# NETWORK POLICIES (Optional - for network segmentation)
# ============================================================================

# Allow traffic within Boomi namespace
resource "kubernetes_network_policy" "boomi_internal" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name      = "boomi-internal"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {}
    }

    policy_types = ["Ingress", "Egress"]

    # Allow traffic from within boomi namespace
    ingress {
      from {
        pod_selector {
          match_labels = {}
        }
      }
    }

    # Allow traffic from keda namespace (for metrics)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.keda_namespace
          }
        }
      }
    }

    # Allow outbound traffic
    egress {
      to {
        pod_selector {
          match_labels = {}
        }
      }
    }

    # Allow DNS egress
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow external egress
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "169.254.169.254/32" # Block AWS metadata endpoint
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# RESOURCE QUOTAS (Optional - for resource limiting)
# ============================================================================

resource "kubernetes_resource_quota" "boomi" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name      = "boomi-quota"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "100"
      "requests.memory" = "200Gi"
      "limits.cpu"      = "200"
      "limits.memory"   = "400Gi"
      "pods"            = "500"
      "services"        = "50"
      "persistentvolumeclaims" = "10"
    }

    scope_selector {
      match_expression {
        operator       = "In"
        scope_name     = "PriorityClass"
        values         = ["high-priority", "medium-priority"]
      }
    }
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# LIMIT RANGES (Optional - for per-pod resource limits)
# ============================================================================

resource "kubernetes_limit_range" "boomi" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name      = "boomi-limits"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  spec {
    limit {
      type = "Pod"
      max = {
        cpu    = "2"
        memory = "4Gi"
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }

    limit {
      type = "Container"
      max = {
        cpu    = "2"
        memory = "4Gi"
      }
      min = {
        cpu    = "50m"
        memory = "64Mi"
      }
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "250m"
        memory = "256Mi"
      }
    }

    limit {
      type = "PersistentVolumeClaim"
      max = {
        storage = "100Gi"
      }
      min = {
        storage = "1Gi"
      }
    }
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# CONFIG MAPS
# ============================================================================

# ConfigMap for Boomi configuration
resource "kubernetes_config_map" "boomi_config" {
  metadata {
    name      = "boomi-config"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  data = {
    "atom-name"                  = var.boomi_atom_name
    "cloud-name"                 = var.boomi_cloud_name
    "max-workers"                = var.boomi_max_workers
    "min-workers"                = var.boomi_min_workers
    "max-running-executions"     = var.boomi_max_running_executions
    "elastic-scaling-threshold"  = var.boomi_elastic_scaling_threshold
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# SECRETS
# ============================================================================

# Boomi install token secret (should be rotated regularly)
resource "kubernetes_secret" "boomi_install_token" {
  metadata {
    name      = "runtime-token"
    namespace = kubernetes_namespace.boomi.metadata[0].name
  }

  type = "Opaque"

  data = {
    token = var.boomi_install_token
  }

  depends_on = [kubernetes_namespace.boomi]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "boomi_namespace" {
  description = "Boomi namespace name"
  value       = kubernetes_namespace.boomi.metadata[0].name
}

output "keda_namespace" {
  description = "KEDA namespace name"
  value       = kubernetes_namespace.keda.metadata[0].name
}

output "monitoring_namespace" {
  description = "Monitoring namespace name"
  value       = var.enable_monitoring ? kubernetes_namespace.monitoring[0].metadata[0].name : null
}

output "boomi_service_account" {
  description = "Boomi workload service account name"
  value       = kubernetes_service_account.boomi_workload.metadata[0].name
}
