> **Deployment review:** This configuration is not yet certified for a fresh
> deployment. Read [DEPLOYMENT_REVIEW.md](DEPLOYMENT_REVIEW.md) before following
> the historical instructions below. Some chart values and version examples
> still require verification. Do not treat an infrastructure apply as proof of
> working Boomi elastic executions.

# Boomi Elastic Executions - EKS Terraform Automation

Complete Terraform automation for deploying Boomi Elastic Runtime with Kubernetes Event Driven Autoscaler (KEDA) on AWS EKS.

## Overview

This Terraform configuration automates the deployment of:
- AWS EKS Cluster with managed node groups
- VPC with public/private subnets and NAT Gateways
- Elastic File System (EFS) for shared storage
- KEDA for elastic scaling of worker pods
- Boomi Elastic Controller and Runtime Cloud
- Optional Prometheus/Grafana monitoring stack
- Cluster Autoscaler for automatic node scaling
- AWS Load Balancer Controller for ingress

## Prerequisites

### Required Tools
- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- kubectl >= 1.27
- Helm >= 3.0

### AWS Requirements
- AWS account with appropriate IAM permissions
- Sufficient EC2 capacity in target region
- VPC quotas not exceeded

### Boomi Requirements
- Boomi Platform account with Cloud Management feature enabled
- Elastic Execution feature flag enabled (obtained via Early Access)
- User role with "Cloud Management" privilege

## Quick Start

### 1. Clone or Download Configuration
```bash
git clone <repository-url> boomi-elastic-eks
cd boomi-elastic-eks
```

### 2. Generate Boomi Install Token

1. Log in to [Boomi Platform](https://platform.boomi.com)
2. Navigate to **Manage** > **Cloud Management**
3. Click **Create Cloud** (or select existing cloud)
4. Click **Install Cloud Molecule**
5. Click **Generate Install Token**
6. Copy the generated token (valid for 24 hours)

### 3. Configure Terraform Variables

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

**CRITICAL**: Update the following in `terraform.tfvars`:
- `boomi_install_token` - Paste your generated token
- `aws_region` - Your target AWS region
- `environment` - dev, staging, or prod
- `grafana_admin_password` - Strong password for Grafana (production)

### 4. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan -out=tfplan

# Apply configuration (takes 20-30 minutes)
terraform apply tfplan
```

### 5. Configure kubectl

```bash
# Get the command from Terraform output
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Verify cluster access
kubectl get nodes
```

### 6. Verify Deployment

```bash
# Check cluster status
kubectl get nodes -o wide

# Check KEDA installation
kubectl get pods -n keda

# Check Boomi components
kubectl get pods -n boomi

# Check storage
kubectl get pvc -n boomi

# Check services
kubectl get svc -n boomi
```

### 7. Configure in Boomi Platform

1. Log in to Boomi Platform
2. Go to **Manage** > **Runtime Management**
3. Verify your cloud appears as "Online"
4. Create an **Environment**
5. Create an **Attachment** in your new cloud
6. Go to cloud properties > **Advanced tab**
7. Add property: **Execution Workers Enabled** (enable it)
8. Save and restart the cloud
9. Configure **Attachment Quotas**:
   - **Atom Workers**: Set to at least 1
   - **Minimum Atom Workers**: Set to at least 1
   - **Elastic Scaling Threshold**: Default to 100%

## File Structure

```
boomi-elastic-eks/
├── main.tf                    # VPC and EKS cluster setup
├── iam.tf                     # IAM roles and policies
├── kubernetes.tf              # Kubernetes namespaces and RBAC
├── storage.tf                 # EFS and storage configuration
├── helm.tf                    # Helm releases (KEDA, Boomi, monitoring)
├── variables.tf               # Variable definitions
├── outputs.tf                 # Terraform outputs
├── terraform.tfvars.example   # Example configuration (copy to terraform.tfvars)
├── config.yaml.example        # Configuration reference (for documentation)
├── versions.tf                # Provider versions (create if needed)
└── README.md                  # This file
```

## Configuration Customization

### Changing Cluster Size

Edit `terraform.tfvars`:

```hcl
# For smaller clusters (dev)
boomi_node_group_config = {
  name           = "boomi-cloud-nodes"
  instance_types = ["t3.large"]
  desired_size   = 2
  min_size       = 2
  max_size       = 4
  disk_size      = 50
}

# For larger clusters (production)
boomi_node_group_config = {
  name           = "boomi-cloud-nodes"
  instance_types = ["t3.2xlarge"]
  desired_size   = 5
  min_size       = 5
  max_size       = 20
  disk_size      = 200
}
```

### Adjusting Worker Quotas

Edit `terraform.tfvars`:

```hcl
boomi_max_workers               = 20    # Max workers per attachment
boomi_min_workers               = 2     # Minimum (0 = scale to zero)
boomi_max_running_executions    = 15    # Executions per worker
boomi_elastic_scaling_threshold = 80    # Percentage to trigger scaling
```

### Enabling/Disabling Features

Edit `terraform.tfvars`:

```hcl
enable_monitoring                    = true   # Prometheus/Grafana
enable_cluster_autoscaler           = true   # Automatic node scaling
enable_aws_load_balancer_controller = true   # ALB ingress
enable_efs                          = true   # Shared file system
enable_kms_encryption               = true   # Encryption at rest
```

## Monitoring and Access

### Grafana Dashboards

After deployment, access Grafana:

```bash
# Port-forward Grafana service
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# Open browser
open http://localhost:3000

# Login
# Username: admin
# Password: <your grafana_admin_password>
```

### Prometheus Metrics

Access Prometheus for custom metrics:

```bash
# Port-forward Prometheus service
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090

# Open browser
open http://localhost:9090
```

### View Boomi Logs

```bash
# Cloud pod logs
kubectl logs -n boomi -l app=runtime-cloud -f --tail=100

# Elastic controller logs
kubectl logs -n boomi -l app=runtime-elastic-controller -f --tail=100

# Worker pod logs
kubectl logs -n boomi -l app=worker -f --tail=100
```

### Monitor KEDA Scaling

```bash
# Watch KEDA ScaledObjects
kubectl get scaledobjects -n boomi -w

# View HPA status
kubectl get hpa -n boomi -w

# Check KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator -f --tail=100
```

## Maintenance

### Cluster Updates

Update Kubernetes version:

```hcl
# In terraform.tfvars
eks_cluster_version = "1.28"

# Apply changes
terraform apply
```

### Scaling Nodes

Modify node group configuration:

```hcl
boomi_node_group_config = {
  # ...
  desired_size = 5  # Increase from 3
  max_size     = 10 # Increase from 6
  # ...
}

# Apply changes
terraform apply
```

### Updating Helm Charts

Update versions in `terraform.tfvars`:

```hcl
helm_keda_version = "2.14.0"  # Update KEDA
helm_prometheus_version = "55.0.0"  # Update Prometheus
```

### Backup EFS

The configuration includes optional AWS Backup integration. To enable:

1. Create an AWS Backup plan in the console
2. Assign EFS file system to the plan
3. Or use Terraform variable: `enable_backup = true`

## Troubleshooting

### Cluster Creation Fails

```bash
# Check AWS CloudFormation events
aws cloudformation describe-stack-events --stack-name <cluster-name>

# Check Terraform logs
terraform plan -out=debug.tfplan -json | jq
```

### Boomi Pods Not Running

```bash
# Check pod status
kubectl describe pod -n boomi <pod-name>

# Check events
kubectl get events -n boomi --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n boomi <pod-name> --previous
```

### EFS Mount Issues

```bash
# Verify EFS CSI driver
kubectl get daemonset -n kube-system | grep efs

# Check mount targets
aws efs describe-mount-targets --file-system-id <efs-id>

# Test EFS access from pod
kubectl run -it -n boomi test-efs --image=busybox -- sh
# Inside pod: mount | grep nfs
```

### Workers Not Scaling

```bash
# Check KEDA ScaledObject
kubectl get scaledobject -n boomi -o yaml

# Check HPA status
kubectl get hpa -n boomi -o wide

# Check KEDA metrics
kubectl top pods -n boomi

# View KEDA logs for errors
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator
```

### High Costs

```bash
# Check running pods
kubectl top pods -A

# Review node usage
kubectl describe nodes

# Consider:
# - Reducing max_workers
# - Setting min_workers to 0 (scale to zero)
# - Using smaller instance types
# - Enabling cluster autoscaler to remove unused nodes
```

## Security Best Practices

### Before Production Deployment

- [ ] Change `grafana_admin_password` to a strong password
- [ ] Enable `enable_kms_encryption = true`
- [ ] Set `environment = "prod"`
- [ ] Use larger instance types (t3.xlarge or better)
- [ ] Enable network policies
- [ ] Restrict API access (add to `allowed_cidrs` in security group)
- [ ] Enable VPC Flow Logs for audit
- [ ] Configure CloudWatch alarms
- [ ] Implement backup strategy for EFS
- [ ] Rotate Boomi install token regularly
- [ ] Review IAM roles and policies
- [ ] Enable S3 bucket versioning for Terraform state

### Terraform State Management

Store state in S3 with locking:

```hcl
# Create backend.tf
terraform {
  backend "s3" {
    bucket         = "boomi-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Cost Optimization

### Recommendations

1. **Use Reserved Instances** for predictable workloads
2. **Enable Savings Plans** for compute
3. **Set appropriate max_workers** to limit scaling
4. **Use on-demand for bursty workloads**
5. **Schedule cluster down during off-hours** (dev/staging)
6. **Monitor with Cost Explorer** in AWS console
7. **Set CloudWatch alarms** for cost anomalies
8. **Delete unused resources** regularly

### Estimated Costs (Monthly)

**Development (t3.large)**: $200-300
**Staging (t3.xlarge)**: $400-500
**Production (t3.2xlarge x 5)**: $2000-3000

*Costs vary by region and actual usage. Use AWS Cost Calculator for estimates.*

## Destroying Infrastructure

⚠️ **WARNING**: This will delete ALL resources including:
- EKS cluster and all workloads
- VPC and all networking
- EFS and all stored data
- RDS (if configured)
- All Boomi processes running on this cluster

```bash
# Backup critical data first!
# Export processes from Boomi Platform

# List what will be destroyed
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Confirm deletion
# Type: yes
```

## Support and Documentation

### Boomi Resources
- [Boomi Elastic Executions Setup Guide](https://help.boomi.com/)
- [Boomi Platform Documentation](https://help.boomi.com/)
- [Community Forums](https://community.boomi.com/)

### Kubernetes Resources
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [KEDA Documentation](https://keda.sh/)
- [Kubernetes Official Docs](https://kubernetes.io/docs/)

### Terraform Resources
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Helm Provider Documentation](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/state.html)

## Contributing

For improvements or issues:
1. Test changes in dev/staging first
2. Document all modifications
3. Update version numbers
4. Create pull request with detailed description

## License

This Terraform configuration is provided as-is. Refer to your Boomi license agreement.

## Version History

- **v1.0** (2024) - Initial release with EKS, KEDA, Boomi components
  - EKS 1.27
  - KEDA 2.13.0
  - Boomi Runtime Cloud 5.1.1
  - Elastic Controller 0.1.32

## Contact

For Boomi-specific issues, contact [Boomi Support](https://boomi.atlassian.net/).
For Terraform issues, refer to the troubleshooting section above.

