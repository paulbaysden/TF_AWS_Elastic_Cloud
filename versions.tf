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

# Provider selections have not been validated in a live deployment.
# Run terraform init and terraform validate, then commit .terraform.lock.hcl.
