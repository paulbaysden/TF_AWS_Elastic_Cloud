> **Deployment review:** This configuration is not yet certified for a fresh
> deployment. Read [DEPLOYMENT_REVIEW.md](DEPLOYMENT_REVIEW.md) before following
> the historical instructions below. Some chart values and version examples
> still require verification. Do not treat an infrastructure apply as proof of
> working Boomi elastic executions.

# Boomi Elastic Executions on EKS - Complete Deployment Guide

## Table of Contents
1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Phase 1: AWS Account Preparation](#phase-1-aws-account-preparation)
3. [Phase 2: Generate Boomi Install Token](#phase-2-generate-boomi-install-token)
4. [Phase 3: Terraform Configuration](#phase-3-terraform-configuration)
5. [Phase 4: Deploy Infrastructure](#phase-4-deploy-infrastructure)
6. [Phase 5: Verify Deployment](#phase-5-verify-deployment)
7. [Phase 6: Boomi Platform Configuration](#phase-6-boomi-platform-configuration)
8. [Phase 7: Testing and Validation](#phase-7-testing-and-validation)
9. [Troubleshooting](#troubleshooting)
10. [Post-Deployment](#post-deployment)

---

## Pre-Deployment Checklist

### AWS Requirements
- [ ] AWS account with billing enabled
- [ ] IAM user with sufficient permissions (EC2, EKS, VPC, IAM, EFS, CloudWatch, KMS)
- [ ] Target region has sufficient service quotas:
  - [ ] EC2 instances (check quota for chosen instance types)
  - [ ] VPC (default is usually sufficient)
  - [ ] Elastic IPs (need 2+ for NAT gateways)
  - [ ] EFS (if enabling shared storage)

### Local Environment
- [ ] Terraform installed (version >= 1.0)
  ```bash
  terraform --version
  ```
- [ ] AWS CLI installed and configured
  ```bash
  aws --version
  aws sts get-caller-identity
  ```
- [ ] kubectl installed
  ```bash
  kubectl version --client
  ```
- [ ] Helm installed
  ```bash
  helm version
  ```
- [ ] Git installed (for version control)
  ```bash
  git --version
  ```

### Boomi Requirements
- [ ] Boomi Platform account access
- [ ] Cloud Management feature enabled (verify with Boomi support)
- [ ] Elastic Execution feature flag enabled (Early Access program)
- [ ] User account has "Cloud Management" privilege

### Knowledge Requirements
- [ ] Basic understanding of Terraform
- [ ] Basic Kubernetes/kubectl knowledge
- [ ] Understanding of AWS networking (VPCs, subnets, security groups)
- [ ] Familiarity with Boomi Platform basics

---

## Phase 1: AWS Account Preparation

### Step 1.1: Verify AWS Credentials

```bash
# Configure AWS credentials (choose one method)

# Option A: AWS CLI interactive setup
aws configure

# Option B: Set environment variables
export AWS_REGION=us-east-2
export AWS_PROFILE=default

# Option C: Use AWS SSO
aws sso login --profile boomi-prod

# Verify access
aws sts get-caller-identity
```

Expected output:
```json
{
  "UserId": "AIDAI...",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/username"
}
```

### Step 1.2: Check AWS Service Quotas

```bash
# Check EC2 instance quota for your target instance types
aws service-quotas list-service-quotas \
  --service-code ec2 \
  --filters Name=QuotaName,Values="Running On-Demand t3 instances" \
  --region us-east-2

# Check VPC quota
aws service-quotas list-service-quotas \
  --service-code vpc \
  --filters Name=QuotaName,Values="VPCs per Region" \
  --region us-east-2

# Check EFS quota
aws service-quotas list-service-quotas \
  --service-code elasticfilesystem \
  --filters Name=QuotaName,Values="File systems per account" \
  --region us-east-2
```

### Step 1.3: Create S3 Bucket for Terraform State (Recommended)

```bash
# Create bucket for state
aws s3api create-bucket \
  --bucket boomi-terraform-state-$(date +%s) \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket boomi-terraform-state-XXXXX \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket boomi-terraform-state-XXXXX \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket boomi-terraform-state-XXXXX \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## Phase 2: Generate Boomi Install Token

### Step 2.1: Log in to Boomi Platform

1. Navigate to [https://platform.boomi.com](https://platform.boomi.com)
2. Enter your Boomi credentials
3. Click **Sign In**

### Step 2.2: Create Cloud in Boomi Platform

1. Click **Manage** in the top menu
2. Select **Cloud Management** from the dropdown
3. Click **Create Cloud** (top right button)
4. Fill in Cloud details:
   - **Cloud Name**: `ElasticCloud` (or your preferred name)
   - **Cluster Type**: Select appropriate type
   - **Description**: "EKS-based elastic runtime"
5. Click **Save**

### Step 2.3: Generate Install Token

1. On the Cloud Management page, locate your newly created cloud
2. Click **Install Cloud Molecule** button
3. Click **Generate Install Token** button
4. **IMPORTANT**: Copy the full token immediately
   - Token is only displayed once
   - Token expires after 24 hours
   - If you miss it, generate a new one

Example token format:
```
2BfY3h5J8kL9pQ2mN6xR4vS7wT0aB3cD5eF8gH1jK4lM7nO0pQ3sR6tU9vW2xY5zA8bC1dE4
```

### Step 2.4: Verify Token Properties

Before proceeding, verify:
- [ ] Token is copied completely (no spaces at beginning/end)
- [ ] Token is from the correct cloud
- [ ] Token was generated less than 24 hours ago
- [ ] You have the full token (usually 70+ characters)

---

## Phase 3: Terraform Configuration

### Step 3.1: Clone or Download Configuration

```bash
# Clone from repository
git clone <repository-url> boomi-elastic-eks
cd boomi-elastic-eks

# Or download and extract zip file
unzip boomi-elastic-eks.zip
cd boomi-elastic-eks
```

### Step 3.2: Review Files

```bash
# List configuration files
ls -la

# Expected files:
# - main.tf
# - iam.tf
# - kubernetes.tf
# - storage.tf
# - helm.tf
# - variables.tf
# - outputs.tf
# - versions.tf
# - terraform.tfvars.example
# - config.yaml.example
# - README.md
# - DEPLOYMENT_GUIDE.md
```

### Step 3.3: Create terraform.tfvars

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

### Step 3.4: Configure Required Variables

Edit `terraform.tfvars` and update these **CRITICAL** variables:

```hcl
# AWS Configuration
aws_region  = "us-east-2"        # Your target region
aws_profile = "default"           # Your AWS profile
environment = "dev"               # dev, staging, prod

# BOOMI INSTALL TOKEN (REQUIRED)
boomi_install_token = "2BfY3h5J8kL9pQ2mN6xR4vS7..." # Paste your token

# Boomi Configuration
boomi_cloud_name = "ElasticCloud"
boomi_atom_name  = "ElasticCloud"

# Node Configuration (optional, but recommended)
system_node_group_config = {
  instance_types = ["t3.large"]
  desired_size   = 2
  min_size       = 2
  max_size       = 4
}

boomi_node_group_config = {
  instance_types = ["t3.xlarge"]
  desired_size   = 3
  min_size       = 3
  max_size       = 6
}

# Monitoring
enable_monitoring       = true
grafana_admin_password  = "YourSecurePassword123!"

# Optional Features
enable_cluster_autoscaler = true
enable_kms_encryption     = true
```

### Step 3.5: Review Configuration

```bash
# Display your configuration (without sensitive values)
grep -v "^#" terraform.tfvars | grep "=" | head -20

# Verify key values are set
grep "boomi_install_token" terraform.tfvars
grep "aws_region" terraform.tfvars
grep "boomi_cloud_name" terraform.tfvars
```

### Step 3.6: Secure terraform.tfvars

```bash
# Add to .gitignore to prevent accidental commit
echo "terraform.tfvars" >> .gitignore

# Restrict file permissions
chmod 600 terraform.tfvars

# Verify it's not tracked by git
git status
```

---

## Phase 4: Deploy Infrastructure

### Step 4.1: Initialize Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Output should show:
# - Terraform version
# - Provider versions
# - Initialization success message
```

### Step 4.2: Validate Configuration

```bash
# Validate syntax and basic checks
terraform validate

# Output should show:
# Success: The configuration is valid
```

### Step 4.3: Format Configuration (Optional)

```bash
# Auto-format Terraform files
terraform fmt -recursive

# This improves readability and consistency
```

### Step 4.4: Review Planned Changes

```bash
# Create and review execution plan
terraform plan -out=tfplan

# This will output:
# - Resources to be created (+ created)
# - Resources to be modified (~ modified)
# - Resources to be destroyed (- destroyed)
#
# Expected for first deployment: ~80-100 resources created
#
# Key resources to verify:
# - aws_vpc
# - aws_eks_cluster
# - aws_eks_node_group (2 groups)
# - aws_efs_file_system
# - helm_release (KEDA, Boomi)
# - kubernetes_namespace
# - kubernetes_service_account
```

### Step 4.5: Save Plan (Important for Production)

```bash
# Already saved as 'tfplan' in previous step
# This is good practice for traceability

# You can also save to named file
terraform plan -out=deployment-$(date +%Y%m%d-%H%M%S).tfplan
```

### Step 4.6: Apply Configuration

⚠️ **POINT OF NO RETURN** - This will create AWS resources and incur costs.

```bash
# Apply the plan (creates resources)
terraform apply tfplan

# This will take 20-30 minutes
# Progress shows:
# 1. VPC creation (2-3 min)
# 2. EKS cluster creation (10-15 min)
# 3. Node group creation (5-10 min)
# 4. Helm releases deployment (5-10 min)

# Monitor progress
# - Check CloudFormation in AWS Console
# - Watch CloudWatch logs
# - Monitor EKS cluster status

# Monitor with commands
watch -n 5 'aws eks describe-cluster --name boomi-elastic-cluster --region us-east-2 --query "cluster.status"'
```

### Step 4.7: Capture Outputs

```bash
# Display Terraform outputs
terraform output

# This shows important values like:
# - EKS cluster endpoint
# - VPC ID
# - Service account names
# - Access commands

# Save outputs to file for reference
terraform output -json > deployment-outputs.json
terraform output -raw kubernetes_config >> cluster-config.sh
```

---

## Phase 5: Verify Deployment

### Step 5.1: Configure kubectl

```bash
# Get EKS cluster credentials
aws eks update-kubeconfig \
  --region us-east-2 \
  --name boomi-elastic-cluster

# Verify configuration
kubectl config current-context

# Should output:
# arn:aws:eks:us-east-2:123456789012:cluster/boomi-elastic-cluster
```

### Step 5.2: Check Cluster Status

```bash
# Verify cluster connectivity
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://...
# CoreDNS is running at https://...

# Check node status
kubectl get nodes -o wide

# Expected output: 5 nodes (2 system + 3 boomi) in Ready state
```

### Step 5.3: Verify Namespaces

```bash
# Check namespaces were created
kubectl get namespaces

# Expected namespaces:
# - boomi
# - keda
# - monitoring (if enabled)
# - kube-system
# - kube-public
# - default

# Verify each namespace
kubectl describe namespace boomi
kubectl describe namespace keda
```

### Step 5.4: Verify KEDA

```bash
# Check KEDA operator pods
kubectl get pods -n keda -o wide

# Expected output:
# - keda-admission-webhooks-... (1/1 Running)
# - keda-operator-... (1/1 Running)
# - keda-operator-metrics-apiserver-... (1/1 Running)

# Check KEDA logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator -f --tail=50
```

### Step 5.5: Verify Boomi Components

```bash
# Check Elastic Controller
kubectl get pods -n boomi -l app=runtime-elastic-controller -o wide

# Expected: 1 pod in Running state

# Check Runtime Cloud
kubectl get pods -n boomi -l app=runtime-cloud -o wide

# Expected: 3 pods in Running state (or your configured replicas)

# Check all Boomi pods
kubectl get all -n boomi

# View pod details
kubectl describe pod -n boomi -l app=runtime-cloud
```

### Step 5.6: Verify Storage

```bash
# Check storage classes
kubectl get storageclass

# Expected: efs-sc and ebs-gp3 classes

# Check persistent volumes
kubectl get pv

# Check persistent volume claims
kubectl get pvc -n boomi

# Expected: runtime-claim bound to runtime-volume

# Verify EFS mount
kubectl get efs

# Check EFS mounting
aws efs describe-mount-targets --file-system-id fs-xxxxx
```

### Step 5.7: Verify RBAC

```bash
# Check service accounts
kubectl get serviceaccount -n boomi

# Expected accounts:
# - boomi-workload-sa
# - boomi-runtime-cloud-sa
# - boomi-elastic-controller-sa

# Check role bindings
kubectl get rolebinding -n boomi

# Check cluster role bindings
kubectl get clusterrolebinding | grep boomi

# Verify IRSA annotations
kubectl describe sa boomi-workload-sa -n boomi

# Should show role ARN annotation
```

### Step 5.8: Verify Monitoring (if enabled)

```bash
# Check monitoring namespace
kubectl get pods -n monitoring

# Expected pods:
# - prometheus-...
# - grafana-...
# - alertmanager-...
# - node-exporter-...

# Check Grafana access
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &

# Test connection
curl http://localhost:3000/login

# Stop port-forward
kill %1
```

### Step 5.9: Check Security Groups

```bash
# Get security group for cluster
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*boomi-elastic*" \
  --region us-east-2

# Verify ingress rules
# Should allow traffic within VPC and from needed sources
```

### Step 5.10: Verify Logs

```bash
# Check EKS cluster logs in CloudWatch
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/eks/boomi-elastic-cluster" \
  --region us-east-2

# View logs
aws logs tail "/aws/eks/boomi-elastic-cluster/cluster" --follow
```

---

## Phase 6: Boomi Platform Configuration

### Step 6.1: Verify Cloud Status

1. Log in to [Boomi Platform](https://platform.boomi.com)
2. Go to **Manage** > **Runtime Management**
3. Locate your cloud: **ElasticCloud**
4. Check status: Should show **Online** (green)
5. Click on cloud name to view details
6. Check cluster nodes: All 3 nodes should show **Online**

### Step 6.2: Create Environment

1. Click **New** button (top right)
2. Select **Environment**
3. Fill in:
   - **Name**: `ElasticTest` (or preferred name)
   - **Classification**: Select **Test**
4. Click **Save**

### Step 6.3: Create Attachment

1. Click **New** button again
2. Select **Basic Runtime**
3. In dialog:
   - **Setup Preference**: "In the Cloud"
   - **Choose a Cloud**: Select **ElasticCloud**
   - **Name**: `ElasticCloud-1` (or preferred name)
4. Click **OK**

### Step 6.4: Attach to Environment

1. New attachment appears under **Unattached Atoms**
2. Select the attachment (checkbox)
3. In **Attach To Environment** dropdown: Select **ElasticTest**
4. Click **Attach** (if available) or similar option
5. Wait for attachment to move to environment

### Step 6.5: Enable Execution Workers

1. Select the cloud molecule: **ElasticCloud**
2. Go to **Properties** panel on right
3. Click **Advanced** tab
4. Click **Add Property**
5. Find: **Execution Workers Enabled**
6. Check the **Enabled** checkbox
7. Click **Save**
8. **IMPORTANT**: Restart the cloud
   - Click three-dot menu next to cloud
   - Select **Restart**
   - Wait for restart to complete (5-10 minutes)

### Step 6.6: Configure Attachment Quotas

1. Go to **Manage** > **Cloud Management**
2. Select **ElasticCloud**
3. Click **Attachment Quotas**
4. For your attachment, set:
   - **Atom Workers** (Required): `10` (or your max)
   - **Minimum Atom Workers** (Optional): `1` (ensures readiness)
   - **Worker Elastic Scaling Threshold**: `100` (start high, adjust later)
5. Click **Save**

---

## Phase 7: Testing and Validation

### Step 7.1: Deploy Test Process

1. Create simple test process in Boomi:
   - **Name**: `TestElasticExecution`
   - One input flow, one output flow
   - Simple mapping (e.g., Pass-through)

2. Deploy to **ElasticTest** environment

3. Version and deploy

### Step 7.2: Execute Batch Process

1. Go to **Manage** > **Process Reporting**
2. Find your test process
3. Click **Test**
4. Click **Run**
5. Wait for completion

While running, check Kubernetes:
```bash
# Monitor job creation
kubectl get jobs -n boomi -w

# Check pods
kubectl get pods -n boomi | grep execution

# View logs
kubectl logs -n boomi -l job-name=<job-name> -f
```

### Step 7.3: Execute Listener Process

1. Create listener test process:
   - **Name**: `TestElasticListener`
   - Configure as Low Latency or Bridge Mode (uses workers)
   - Simple request-response

2. Deploy to **ElasticTest** environment

3. Send test request:
   ```bash
   # Example using curl
   curl -X POST \
     http://<boomi-atom-url>/connectors/container/soap/v1/TestElasticListener \
     -H 'Content-Type: application/xml' \
     -d '<input>test data</input>'
   ```

While running, monitor worker scaling:
```bash
# Watch workers scale
kubectl get deploy -n boomi -l app=worker -w

# View HPA status
kubectl get hpa -n boomi -w

# Monitor KEDA metrics
kubectl top pods -n boomi

# View logs
kubectl logs -n boomi -l app=worker -f
```

### Step 7.4: Monitor Metrics

Access Grafana dashboard:
```bash
# Port forward
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# Open http://localhost:3000
# Login: admin / <your-password>
```

Dashboards to review:
- Kubernetes Cluster Monitoring
- KEDA Metrics
- Pod resource usage

### Step 7.5: Test Scaling

```bash
# Generate load (example with load testing tool)

# While load running, watch scaling
watch -n 2 'kubectl get hpa -n boomi'

# Should see:
# - REFERENCE shows desired replicas increasing
# - Pods creating/running

# Stop load generation and watch scale-down
# Can take 5-10 minutes to scale back to minimum
```

### Step 7.6: Review CloudWatch Logs

```bash
# Check control plane logs
aws logs tail "/aws/eks/boomi-elastic-cluster/cluster" --follow

# Search for errors
aws logs grep "/aws/eks/boomi-elastic-cluster" "ERROR" --follow
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Terraform Apply Fails

**Issue**: Terraform fails during `terraform apply`

**Solutions**:
```bash
# Check service quotas
aws service-quotas list-service-quotas --service-code ec2 --filters Name=QuotaName,Values="Running On-Demand t3 instances" --region us-east-2

# If quota exceeded, request increase:
# AWS Console > Service Quotas > EC2 > Request quota increase

# Check CloudFormation events for details
aws cloudformation describe-stack-events \
  --stack-name boomi-elastic-cluster \
  --region us-east-2

# Re-run with more verbose output
terraform apply -var-file=terraform.tfvars -lock=false -input=false -parallelism=1
```

#### 2. Boomi Cloud Shows "Offline"

**Issue**: Cloud status shows offline in Boomi Platform

**Solutions**:
```bash
# Check pod status
kubectl get pods -n boomi -l app=runtime-cloud

# Check pod logs for connection errors
kubectl logs -n boomi -l app=runtime-cloud -f --tail=100

# Check RBAC permissions
kubectl auth can-i list pods --as=system:serviceaccount:boomi:boomi-workload-sa -n boomi

# Restart cloud from Boomi Platform
# Manage > Runtime Management > ElasticCloud > ... > Restart

# Or restart via kubectl
kubectl delete pods -n boomi -l app=runtime-cloud

# Check cloud configuration
kubectl get configmap -n boomi -o yaml
```

#### 3. Workers Not Scaling

**Issue**: Worker pods don't create or scale

**Solutions**:
```bash
# Check KEDA ScaledObjects
kubectl get scaledobjects -n boomi -o yaml

# Check HPA status
kubectl get hpa -n boomi

# Check HPA details for errors
kubectl describe hpa -n boomi

# Check KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=100

# Check metrics availability
kubectl top pods -n boomi

# Check if metrics-server is running
kubectl get deployment metrics-server -n kube-system
```

#### 4. Persistent Volume Issues

**Issue**: PVC not binding or mount failures

**Solutions**:
```bash
# Check PVC status
kubectl get pvc -n boomi -o wide

# Check PV status
kubectl get pv -o wide

# Describe PVC for events
kubectl describe pvc runtime-claim -n boomi

# Check EFS file system
aws efs describe-file-systems --file-system-id fs-xxxxx

# Verify EFS mount targets
aws efs describe-mount-targets --file-system-id fs-xxxxx

# Check security group for EFS
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test EFS access from pod
kubectl run -it -n boomi test-efs --image=busybox -- sh
# Inside pod: mount | grep nfs
```

#### 5. High Costs

**Issue**: Unexpected AWS costs

**Solutions**:
```bash
# Check running resources
kubectl get all -A --no-headers | wc -l

# Review resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Check for orphaned resources
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# Reduce node count
# Edit terraform.tfvars:
# boomi_node_group_config.desired_size = 2  # Reduce from 3

# Reduce max workers
# boomi_max_workers = 5  # Reduce from 10

# Apply changes
terraform apply

# Monitor costs in AWS Console
# AWS > Billing & Cost Management > Cost Explorer
```

---

## Post-Deployment

### Immediate Actions (Day 1)

```bash
# 1. Back up Terraform state
aws s3 cp terraform.tfstate s3://boomi-backups/$(date +%Y%m%d)-terraform.tfstate

# 2. Document cluster information
terraform output -json > cluster-info-$(date +%Y%m%d).json

# 3. Create kubectl config backup
cp ~/.kube/config ~/.kube/config.backup-$(date +%Y%m%d)

# 4. Test disaster recovery
# Delete a non-critical pod
# Verify it auto-restarts

# 5. Set CloudWatch alarms
aws cloudwatch put-metric-alarm \
  --alarm-name boomi-cluster-cpu-high \
  --alarm-description "Alert when cluster CPU is high" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

### Week 1 Actions

- [ ] Set up automated backups for EFS
- [ ] Configure CloudWatch alerts
- [ ] Document custom configurations
- [ ] Train team on kubectl commands
- [ ] Schedule regular cost reviews
- [ ] Plan capacity for peak loads

### Monthly Maintenance

```bash
# Update security patches
# 1. Check for available Kubernetes updates
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.27

# 2. Update Helm charts
helm repo update
helm upgrade <release-name> <chart>

# 3. Check for CVEs
# AWS Security Hub > AWS Config > Compliance status

# 4. Review logs
# CloudWatch > Logs > Insights > Run queries

# 5. Validate disaster recovery
# Test backup restoration
```

### Quarterly Actions

- [ ] Capacity planning review
- [ ] Security audit
- [ ] Cost optimization review
- [ ] Kubernetes version upgrade planning
- [ ] Documentation update
- [ ] Team training/certification

---

## End of Deployment Guide

For more information:
- See README.md for general information
- Check TROUBLESHOOTING section above
- Review Boomi documentation
- AWS EKS Best Practices: https://aws.github.io/aws-eks-best-practices/

