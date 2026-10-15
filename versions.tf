# ============================================================================
# TERRAFORM VERSION AND PROVIDER REQUIREMENTS
# ============================================================================
#
# This file specifies the required versions for Terraform and all providers
# to ensure consistent deployments across different environments and team members.
#
# Update these versions carefully and test thoroughly before deploying.
#

terraform {
  required_version = ">= 1.0, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # Minimum: 5.0.0
      # Recommended: Latest 5.x
      # 
      # AWS Provider Changelog: https://github.com/hashicorp/terraform-provider-aws/releases
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
      # Minimum: 2.23.0
      # Recommended: Latest 2.x
      #
      # Kubernetes Provider Changelog: https://github.com/hashicorp/terraform-provider-kubernetes/releases
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
      # Minimum: 2.11.0
      # Recommended: Latest 2.x
      #
      # Helm Provider Changelog: https://github.com/hashicorp/terraform-provider-helm/releases
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
      # Minimum: 1.14.0
      # Recommended: Latest 1.x
      #
      # kubectl Provider Changelog: https://github.com/gavinbunney/terraform-provider-kubectl/releases
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
      # Used for OIDC provider certificate
      # Minimum: 4.0.0
      # Recommended: Latest 4.x
    }
  }
}

# ============================================================================
# COMPATIBILITY MATRIX
# ============================================================================
#
# Test combinations before major version updates:
#
# Terraform | AWS Provider | Kubernetes | Helm  | kubectl
# =========================================================
# 1.0+      | 5.0+        | 2.23+      | 2.11+ | 1.14+   ✓ CURRENT
# 1.0+      | 4.x         | 2.19+      | 2.8+  | 1.10+   ✓ PREVIOUS
#
# ✓ = Tested and supported
# • = Known to work but not actively tested
# ✗ = Not recommended due to breaking changes or conflicts
#

# ============================================================================
# UPGRADE INSTRUCTIONS
# ============================================================================
#
# To upgrade provider versions:
#
# 1. Update version constraint in this file
# 2. Run: terraform init -upgrade
# 3. Review: terraform plan -out=upgrade.tfplan
# 4. Test in dev environment first
# 5. Review changelog for breaking changes
# 6. Apply: terraform apply upgrade.tfplan
#
# IMPORTANT: Always backup terraform.tfstate before upgrading!
#

# ============================================================================
# VERSION HISTORY
# ============================================================================
#
# v1.0 (2024)
# - Terraform >= 1.0
# - AWS Provider >= 5.0
# - Kubernetes Provider >= 2.23
# - Helm Provider >= 2.11
# - kubectl Provider >= 1.14
#
# Justification:
# - AWS 5.0+ provides improved EKS support and IRSA features
# - Kubernetes 2.23+ has stable Kubernetes 1.27+ support
# - Helm 2.11+ supports latest chart features
# - kubectl 1.14+ compatible with EKS 1.27+
#
