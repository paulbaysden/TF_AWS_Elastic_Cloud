# ============================================================================
# ELASTIC FILE SYSTEM (EFS)
# ============================================================================

resource "aws_efs_file_system" "runtime" {
  count              = var.enable_efs ? 1 : 0
  creation_token     = "${var.project_name}-runtime"
  performance_mode   = var.efs_performance_mode
  throughput_mode    = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput_mibps : null
  encrypted          = true
  kms_key_id         = var.enable_kms_encryption ? aws_kms_key.eks[0].arn : null

  tags = {
    Name = "${var.project_name}-runtime-efs"
  }

  depends_on = [aws_eks_cluster.main]
}

# EFS Mount Targets (one per private subnet)
resource "aws_efs_mount_target" "runtime" {
  count            = var.enable_efs ? length(aws_subnet.private) : 0
  file_system_id   = aws_efs_file_system.runtime[0].id
  subnet_id        = aws_subnet.private[count.index].id
  security_groups  = [aws_security_group.efs.0.id]

  depends_on = [aws_efs_file_system.runtime]
}

# EFS Access Point for Boomi runtime
resource "aws_efs_access_point" "runtime" {
  count           = var.enable_efs ? 1 : 0
  file_system_id  = aws_efs_file_system.runtime[0].id
  
  posix_user {
    gid = 0
    uid = 0
  }

  root_directory {
    path = "/boomi"
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.project_name}-runtime-ap"
  }

  depends_on = [aws_efs_file_system.runtime]
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  count       = var.enable_efs ? 1 : 0
  name_prefix = "${var.project_name}-efs-"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "NFS access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }
}

# ============================================================================
# EBS CSI DRIVER ADDON
# ============================================================================

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.14.1"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  tags = {
    Name = "${var.project_name}-ebs-csi-driver"
  }

  depends_on = [aws_eks_node_group.system]
}

# ============================================================================
# EFS CSI DRIVER DEPLOYMENT (via Helm - more flexible than addon)
# ============================================================================

resource "helm_release" "efs_csi_driver" {
  count            = var.enable_efs ? 1 : 0
  name             = "aws-efs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart            = "aws-efs-csi-driver"
  version          = "2.5.0"
  namespace        = "kube-system"
  create_namespace = false

  values = [
    jsonencode({
      serviceAccount = {
        create = true
        name   = "efs-csi-controller-sa"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.efs_csi_driver[0].arn
        }
      }
      controller = {
        serviceAccount = {
          create = false
          name   = "efs-csi-controller-sa"
        }
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
      }
      node = {
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
    })
  ]

  depends_on = [
    aws_eks_cluster.main,
    aws_efs_file_system.runtime
  ]
}

# ============================================================================
# STORAGE CLASSES
# ============================================================================

# EFS Storage Class
resource "kubernetes_storage_class" "efs" {
  count = var.enable_efs ? 1 : 0
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Delete"
  allow_volume_expansion = true

  parameters = {
    provisioningMode = "efs"
    fileSystemId     = aws_efs_file_system.runtime[0].id
    directoryPerms   = "700"
    uid              = "0"
    gid              = "0"
  }

  depends_on = [helm_release.efs_csi_driver]
}

# EBS Storage Class (gp3 - fast and cost-effective)
resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  allow_volume_expansion = true
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    iops      = "3000"
    throughput = "125"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# ============================================================================
# KUBERNETES PERSISTENT VOLUME & CLAIM FOR RUNTIME
# ============================================================================

resource "kubernetes_persistent_volume" "runtime" {
  count = var.enable_efs ? 1 : 0
  metadata {
    name = "runtime-volume"
  }

  spec {
    capacity = {
      storage = var.runtime_storage_size
    }

    access_modes = ["ReadWriteMany"]
    storage_class_name = "efs-sc"

    persistent_volume_source {
      nfs {
        path      = "/"
        server    = "${aws_efs_file_system.runtime[0].dns_name}"
      }
    }

    persistent_volume_reclaim_policy = "Retain"
  }

  depends_on = [kubernetes_storage_class.efs]
}

resource "kubernetes_persistent_volume_claim" "runtime" {
  count = var.enable_efs ? 1 : 0
  metadata {
    name      = "runtime-claim"
    namespace = var.boomi_namespace
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "efs-sc"

    resources = {
      requests = {
        storage = var.runtime_storage_size
      }
    }

    volume_name = kubernetes_persistent_volume.runtime[0].metadata[0].name
  }

  depends_on = [kubernetes_persistent_volume.runtime]
}

# ============================================================================
# BACKUP AND RESTORE (Optional - using AWS Backup)
# ============================================================================

# Backup plan for EFS
resource "aws_backup_vault" "efs" {
  count             = var.enable_efs ? 1 : 0
  name              = "${var.project_name}-efs-vault"
  kms_key_arn       = var.enable_kms_encryption ? aws_kms_key.eks[0].arn : null
  
  tags = {
    Name = "${var.project_name}-efs-vault"
  }
}

resource "aws_backup_plan" "efs" {
  count = var.enable_efs ? 1 : 0
  name  = "${var.project_name}-efs-backup"

  rule {
    rule_name         = "daily_backup"
    target_backup_vault_name = aws_backup_vault.efs[0].name
    schedule          = "cron(0 5 * * ? *)"
    start_window      = 60
    completion_window = 300

    lifecycle {
      delete_after = 30
    }
  }

  tags = {
    Name = "${var.project_name}-efs-backup"
  }
}

resource "aws_backup_resource_assignment" "efs" {
  count              = var.enable_efs ? 1 : 0
  name               = "${var.project_name}-efs-backup-assignment"
  backup_plan_id     = aws_backup_plan.efs[0].id
  resources          = ["${aws_efs_file_system.runtime[0].arn}"]

  depends_on = [aws_backup_plan.efs]
}

# ============================================================================
# OUTPUTS FOR STORAGE
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
