# ============================================================================
# HELM REPOSITORIES
# ============================================================================

# ============================================================================
# KEDA (Kubernetes Event Driven Autoscaler)
# ============================================================================

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.helm_keda_version
  namespace        = kubernetes_namespace.keda.metadata[0].name
  create_namespace = false

  values = [
    jsonencode({
      serviceAccount = {
        create = false
        name   = kubernetes_service_account.keda.metadata[0].name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.keda.arn
        }
      }

      operator = {
        replicaCount = 2
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
        nodeSelector = {
          workload = "system"
        }
      }

      metricsServer = {
        enabled = true
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      webhooks = {
        admissionWebhooks = {
          enabled = true
        }
      }

      logLevel = {
        operator = "info"
        metricServer = "info"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.keda,
    kubernetes_service_account.keda,
    aws_eks_node_group.system
  ]

  timeout = 300
}

# ============================================================================
# BOOMI ELASTIC CONTROLLER
# ============================================================================

resource "helm_release" "boomi_elastic_controller" {
  name             = "runtime-elastic-controller-release"
  chart            = "oci://registry-1.docker.io/boomi/runtime-elastic-controller"
  version          = var.helm_boomi_elastic_controller_version
  namespace        = kubernetes_namespace.boomi.metadata[0].name
  create_namespace = false

  values = [
    jsonencode({
      fullnameOverride = "runtime-elastic-controller"

      replicaCount = var.boomi_elastic_controller_replicas

      image = {
        tag = var.boomi_elastic_controller_image_tag
      }

      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.boomi_workload.metadata[0].name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.boomi_workload.arn
        }
      }

      nodeSelector = {
        workload = "system"
      }

      tolerations = [
        {
          key      = "boomi-cloud"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app"
                      operator = "In"
                      values   = ["runtime-elastic-controller"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }

      # Pod customization hooks
      boomi = {
        runner = {
          resources = {
            requests = {
              cpu    = var.boomi_runner_cpu_request
              memory = var.boomi_runner_memory_request
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        worker = {
          resources = {
            requests = {
              cpu    = var.boomi_worker_cpu_request
              memory = var.boomi_worker_memory_request
            }
            limits = {
              cpu    = "2000m"
              memory = "1500Mi"
            }
          }
        }

        execution = {
          # Customizations for both runner and worker pods
          # This will be expanded based on needs
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.boomi,
    kubernetes_service_account.boomi_workload,
    helm_release.keda
  ]

  timeout = 300
}

# ============================================================================
# BOOMI RUNTIME CLOUD
# ============================================================================

resource "helm_release" "boomi_runtime_cloud" {
  name             = "runtime-cloud-release"
  chart            = "oci://registry-1.docker.io/boomi/runtime-cloud"
  version          = var.helm_boomi_runtime_cloud_version
  namespace        = kubernetes_namespace.boomi.metadata[0].name
  create_namespace = false

  values = [
    jsonencode({
      fullnameOverride = "runtime-cloud"

      statefulSet = {
        replicas = var.boomi_runtime_cloud_replicas
      }

      image = {
        tag = var.boomi_runtime_cloud_image_tag
      }

      resources = {
        requests = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "2000m"
          memory = "4Gi"
        }
      }

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.boomi_workload.metadata[0].name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.boomi_workload.arn
        }
      }

      # Boomi configuration
      boomi = {
        installTokenSecretRef = {
          name = "runtime-token"
          key  = "token"
        }
        atomName = var.boomi_atom_name

        # Container properties for enabling elastic executions
        containerPropertiesOverrides = join("|", [
          "com.boomi.container.processExecMode=ELASTIC",
          "com.boomi.container.elastic.controllerHost=runtime-elastic-controller",
          "com.boomi.container.elastic.cloudHost=runtime-cloud-internal"
        ])
      }

      # Storage configuration
      persistence = {
        enabled      = var.enable_efs
        storageClass = var.enable_efs ? "efs-sc" : "ebs-gp3"
        accessModes  = ["ReadWriteMany"]
        size         = var.runtime_storage_size
        
        existingClaim = var.enable_efs ? "runtime-claim" : null
      }

      # Pod Disruption Budget for high availability
      podDisruptionBudget = {
        enabled = true
        minAvailable = 1
      }

      # Horizontal Pod Autoscaler (typically disabled for cloud pods)
      hpa = {
        enabled = false
        minReplicas = var.boomi_runtime_cloud_replicas
        maxReplicas = var.boomi_runtime_cloud_replicas * 2
        targetCPUUtilizationPercentage = 80
      }

      # Node affinity
      nodeSelector = {
        workload = "boomi-cloud"
      }

      tolerations = [
        {
          key      = "boomi-cloud"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app"
                      operator = "In"
                      values   = ["runtime-cloud"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }

      # Services
      service = {
        type = "ClusterIP"
        ports = [
          {
            name       = "web"
            port       = 9090
            targetPort = 9090
          }
        ]
      }

      # Internal service for inter-pod communication
      internalService = {
        enabled = true
        name    = "runtime-cloud-internal"
        type    = "ClusterIP"
      }

      # Logging
      logging = {
        level = "INFO"
      }

      # Probes
      livenessProbe = {
        httpGet = {
          path = "/_admin/status"
          port = 9090
        }
        initialDelaySeconds = 60
        periodSeconds       = 10
        timeoutSeconds      = 5
        failureThreshold    = 3
      }

      readinessProbe = {
        httpGet = {
          path = "/_admin/status"
          port = 9090
        }
        initialDelaySeconds = 30
        periodSeconds       = 5
        timeoutSeconds      = 5
        failureThreshold    = 2
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.boomi,
    kubernetes_service_account.boomi_workload,
    kubernetes_secret.boomi_install_token,
    kubernetes_persistent_volume_claim.runtime,
    aws_eks_node_group.boomi_cloud,
    helm_release.boomi_elastic_controller
  ]

  timeout = 600
}

# ============================================================================
# PROMETHEUS & GRAFANA (Optional Monitoring Stack)
# ============================================================================

resource "helm_release" "kube_prometheus_stack" {
  count            = var.enable_monitoring ? 1 : 0
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.helm_prometheus_version
  namespace        = kubernetes_namespace.monitoring[0].metadata[0].name
  create_namespace = false

  values = [
    jsonencode({
      prometheus = {
        prometheusSpec = {
          retention           = "15d"
          retentionSize       = "10GB"
          scrapeInterval      = "30s"
          evaluationInterval  = "30s"
          externalLabels = {
            cluster  = var.eks_cluster_name
            environment = var.environment
          }

          resources = {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "ebs-gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }

          nodeSelector = {
            workload = "system"
          }

          tolerations = [
            {
              key      = "boomi-cloud"
              operator = "Equal"
              value    = "true"
              effect   = "NoSchedule"
            }
          ]
        }
      }

      grafana = {
        enabled = true
        adminPassword = var.grafana_admin_password
        
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }

        nodeSelector = {
          workload = "system"
        }

        tolerations = [
          {
            key      = "boomi-cloud"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }
        ]

        persistence = {
          enabled      = true
          storageClassName = "ebs-gp3"
          size         = "10Gi"
        }

        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                url       = "http://monitoring-kube-prometheus-prometheus:9090"
                access    = "proxy"
                isDefault = true
              }
            ]
          }
        }
      }

      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "ebs-gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }
        }
      }

      nodeExporter = {
        enabled = true
      }

      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.keda
  ]

  timeout = 300
}

# ============================================================================
# CLUSTER AUTOSCALER (Optional)
# ============================================================================

resource "helm_release" "cluster_autoscaler" {
  count      = var.enable_cluster_autoscaler ? 1 : 0
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.32.4"
  namespace  = "kube-system"

  values = [
    jsonencode({
      autoDiscovery = {
        clusterName = var.eks_cluster_name
      }

      image = {
        tag = var.cluster_autoscaler_version
      }

      awsRegion = var.aws_region

      rbac = {
        create = true
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler[0].arn
          }
        }
      }

      replicaCount = 2

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      nodeSelector = {
        workload = "system"
      }

      tolerations = [
        {
          key      = "boomi-cloud"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["aws-cluster-autoscaler"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.system,
    aws_iam_role.cluster_autoscaler
  ]

  timeout = 300
}

# ============================================================================
# AWS LOAD BALANCER CONTROLLER (Optional)
# ============================================================================

resource "helm_release" "aws_load_balancer_controller" {
  count      = var.enable_aws_load_balancer_controller ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "2.6.2"
  namespace  = "kube-system"

  values = [
    jsonencode({
      clusterName = var.eks_cluster_name
      region      = var.aws_region
      vpcId       = aws_vpc.main.id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller[0].arn
        }
      }

      replicaCount = 2

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      nodeSelector = {
        workload = "system"
      }

      tolerations = [
        {
          key      = "boomi-cloud"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["aws-load-balancer-controller"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.system,
    aws_iam_role.aws_load_balancer_controller
  ]

  timeout = 300
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "keda_release_name" {
  description = "KEDA Helm release name"
  value       = helm_release.keda.id
}

output "boomi_elastic_controller_release_name" {
  description = "Boomi Elastic Controller Helm release name"
  value       = helm_release.boomi_elastic_controller.id
}

output "boomi_runtime_cloud_release_name" {
  description = "Boomi Runtime Cloud Helm release name"
  value       = helm_release.boomi_runtime_cloud.id
}

output "monitoring_enabled" {
  description = "Is monitoring stack enabled"
  value       = var.enable_monitoring
}

output "cluster_autoscaler_enabled" {
  description = "Is cluster autoscaler enabled"
  value       = var.enable_cluster_autoscaler
}

