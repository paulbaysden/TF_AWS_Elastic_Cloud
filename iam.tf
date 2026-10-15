# ============================================================================
# EKS CLUSTER IAM ROLE
# ============================================================================

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ============================================================================
# EKS NODE IAM ROLE
# ============================================================================

resource "aws_iam_role" "eks_node" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

# Additional policy for SSM access (for node troubleshooting)
resource "aws_iam_role_policy_attachment" "eks_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node.name
}

# ============================================================================
# EBS CSI DRIVER IRSA
# ============================================================================

data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.project_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json

  tags = {
    Name = "${var.project_name}-ebs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# ============================================================================
# EFS CSI DRIVER IRSA
# ============================================================================

data "aws_iam_policy_document" "efs_csi_driver_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi_driver" {
  count              = var.enable_efs ? 1 : 0
  name               = "${var.project_name}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_driver_assume_role.json

  tags = {
    Name = "${var.project_name}-efs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  count      = var.enable_efs ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver[0].name
}

# ============================================================================
# EFS CSI DRIVER POLICY (Custom for EFS operations)
# ============================================================================

resource "aws_iam_role_policy" "efs_csi_driver_policy" {
  count  = var.enable_efs ? 1 : 0
  name   = "${var.project_name}-efs-csi-driver-policy"
  role   = aws_iam_role.efs_csi_driver[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystem"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# KEDA IRSA
# ============================================================================

data "aws_iam_policy_document" "keda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.keda_namespace}:keda-operator"]
    }
  }
}

resource "aws_iam_role" "keda" {
  name               = "${var.project_name}-keda"
  assume_role_policy = data.aws_iam_policy_document.keda_assume_role.json

  tags = {
    Name = "${var.project_name}-keda"
  }
}

# KEDA needs access to CloudWatch metrics
resource "aws_iam_role_policy" "keda_policy" {
  name   = "${var.project_name}-keda-policy"
  role   = aws_iam_role.keda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# BOOMI WORKLOAD IRSA (if needed for future integrations)
# ============================================================================

data "aws_iam_policy_document" "boomi_workload_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.boomi_namespace}:boomi-workload-sa"]
    }
  }
}

resource "aws_iam_role" "boomi_workload" {
  name               = "${var.project_name}-boomi-workload"
  assume_role_policy = data.aws_iam_policy_document.boomi_workload_assume_role.json

  tags = {
    Name = "${var.project_name}-boomi-workload"
  }
}

# Basic policy for Boomi workloads (expand as needed)
resource "aws_iam_role_policy" "boomi_workload_policy" {
  name   = "${var.project_name}-boomi-workload-policy"
  role   = aws_iam_role.boomi_workload.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# VPC CNI IRSA (for custom CNI configurations if needed)
# ============================================================================

data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.project_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json

  tags = {
    Name = "${var.project_name}-vpc-cni"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

resource "aws_iam_role_policy" "vpc_cni_ipv6_policy" {
  name   = "${var.project_name}-vpc-cni-ipv6"
  role   = aws_iam_role.vpc_cni.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssignIpv6Addresses",
          "ec2:UnassignIpv6Addresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# EKS ADDON ROLE (for managed add-ons if needed in future)
# ============================================================================

data "aws_iam_policy_document" "eks_addon_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:*"]
    }
  }
}

resource "aws_iam_role" "eks_addon" {
  name               = "${var.project_name}-eks-addon"
  assume_role_policy = data.aws_iam_policy_document.eks_addon_assume_role.json

  tags = {
    Name = "${var.project_name}-eks-addon"
  }
}
