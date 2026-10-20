# Deployment readiness review

Reviewed 2026-10-15. Goal: clone, configure AWS authentication and variables,
provide a Boomi cloud installation token, and obtain a working elastic runtime.

**Status: not ready to promise a successful fresh installation.** The local patch
corrects definite code defects, but provider validation, chart rendering and an
AWS/Boomi acceptance deployment remain outstanding. No AWS resources were created.

## Defects corrected in the local patch

| Finding in original repository | Impact | Correction |
| --- | --- | --- |
| `required_providers` in both main.tf and versions.tf; repeated output names across files | Terraform configuration loading fails | Keep provider requirements in versions.tf and shared outputs in outputs.tf |
| `helm_repository` resources | Not supported by the selected HashiCorp Helm provider | Supply repository URLs directly to releases |
| `logging_config` in aws_eks_cluster | Unsupported EKS resource block | Use enabled_cluster_log_types and the existing CloudWatch log group |
| Empty encryption_config when KMS disabled | Invalid encryption configuration | Omit the block when disabled |
| `aws_backup_resource_assignment` | Unsupported AWS resource type | Use aws_backup_selection with a backup IAM role and policy |
| PVC `resources = { ... }` | Wrong Kubernetes provider schema | Use a resources block |
| Unquoted `datasources.yaml` object key | Invalid HCL object key | Quote the key |
| All system Helm workloads select workload=system, but system nodes lack that label | Pods remain Pending | Label the system node group |
| Both Terraform and Helm create keda-operator | Helm service-account ownership conflict | Reuse the Terraform-managed account |
| Boomi chart account names differ from the account used by IRSA/RBAC | Wrong identity and permissions if chart honors these values | Reuse boomi-workload-sa; rendered manifests still need verification |
| EFS controller account creation disabled without creating that account | CSI controller fails | Create and annotate it through the controller chart values |
| Static NFS PV ignores the EFS access point | Access-point identity and directory settings never applied | Use an EFS CSI volume handle with the access point |
| PVC lacks dependency on namespace; PV lacks dependency on mount targets | Creation/mount races | Add dependencies |
| Short-lived EKS data-source token spans long provisioning | Authentication can expire | Use AWS CLI exec authentication with matching region/profile |
| Forced default profile | Environment-based AWS credentials can fail without that profile | Default aws_profile to null |
| Hardcoded EBS addon version | Version may not be compatible with chosen EKS | Query a compatible addon version |
| Old EKS default and autoscaler image not connected to its variable | Obsolete cluster/version mismatch | Require explicit EKS and autoscaler choices and wire the image tag |
| NAT disabled or unequal subnet lists | Invalid NAT indexes or no private-node egress | Require NAT; subnet cardinality still needs validation |
| EFS disabled selects ReadWriteMany on EBS | Unsupported shared-storage design | Require EFS for this runtime topology |
| File named gitignore instead of .gitignore | Credentials, state and saved plans may be committed | Rename it, ignore tfplan/config.yaml, allow provider lockfile commits |
| timestamp() in provider tags | Every plan changes resource tags | Remove the volatile tag |

AL2023 x86-64 node AMIs are explicit in the patch. Use compatible x86-64 instance
types and verify the chosen EKS version supports that AMI family.

## Remaining release blockers

1. **Verify actual Boomi chart contracts.** Pull the exact chart versions in
   terraform.tfvars. Inspect their values and templates, then render the exact
   values from helm.tf. Confirm token secret/key, runtime image repository/tag,
   replica count, service accounts, shared PVC mount, filesystem UID/GID/write
   permissions, service names/ports and controller addresses. Current values
   such as boomi.installTokenSecretRef, statefulSet, persistence and internalService
   have not been proven to be consumed by these charts. Unknown values can be
   ignored by Helm. The patch does not certify these mappings.
2. **Verify execution configuration.** Confirm the property names, delimiters,
   controller/cloud service addresses and execution pod templates against the
   selected Boomi release. Ensure dynamically created runner/worker pods have
   the intended node selectors, tolerations, storage, service accounts and RBAC.
   Editing a ConfigMap alone does not configure Boomi: boomi-config is not mounted
   or referenced by the shown releases. Worker quota variables currently only
   populate that unused ConfigMap. They do not set Boomi platform quotas.
3. **Choose and test a supported version set.** EKS 1.27 is obsolete. Select an
   available EKS version supported by Boomi, match the autoscaler minor version,
   and check KEDA, monitoring, EFS and load-balancer charts. Do not independently
   change everything to latest. Commit the generated provider lockfile after
   validation. EBS addon selection currently uses the latest compatible version,
   so pin its tested version for reproducible releases.
4. **Fix optional controller functionality before enabling it.** The load-balancer
   role uses ElasticLoadBalancingFullAccess rather than the controller's published
   IAM policy, which also includes required EC2/IAM permissions. Autoscaler
   discovery/authorization tags must exist on the backing Auto Scaling Groups;
   EKS node-group tags do not establish that. Neither feature is acceptance-tested.
5. **Validate configuration paths and bootstrap.** Require at least two usable
   availability zones; validate CIDRs, subnet counts, capacity and scaling bounds.
   Private subnet index i currently requires public/NAT index i. A single root
   mixes creation of EKS with Kubernetes/Helm providers: dependencies do not
   guarantee reliable initial provider planning or later destruction. Split AWS
   infrastructure and in-cluster workloads into separate root modules/states for
   the release, with an orchestrating deployment command and reverse destroy order.
6. **Review monitoring admission/network settings.** Monitoring also enables a
   Boomi LimitRange, ResourceQuota and NetworkPolicy. Pod limits can reject real
   chart/generated execution pods; ingress excludes the monitoring namespace.
   These controls should be independently configured and tested. A NetworkPolicy
   object does not prove the cluster CNI is enforcing it.
7. **Complete user documentation.** Replace the historical placeholder clone URL,
   obsolete versions, unsupported enable_backup/allowed_cidrs instructions and
   CloudFormation troubleshooting. config.yaml.example is documentation only.
   enable_vpn_gateway, logging controls and several other inputs do not provision
   the features their descriptions imply. Remove or implement unused inputs.

## Required validation before release

Run locally with Terraform, AWS CLI v2, Helm 3, kubectl, and network access:

```bash
git clone https://github.com/paulbaysden/TF_AWS_Elastic_Cloud.git
cd TF_AWS_Elastic_Cloud
cp terraform.tfvars.example terraform.tfvars
# Configure AWS credentials using environment variables, SSO, or a named profile.
# Keep aws_profile=null for the normal environment credential chain.
# Fill in the EKS/autoscaler versions and other values; use a fresh CLOUD token.
aws sts get-caller-identity
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
helm show values oci://registry-1.docker.io/boomi/runtime-cloud --version <chosen-version>
helm show values oci://registry-1.docker.io/boomi/runtime-elastic-controller --version <chosen-version>
# Render both charts using precisely the values generated by helm.tf, inspect
# manifests, and perform Kubernetes server-side dry runs against the test cluster.
terraform plan -out=tfplan
# Apply only after resolving the blockers above and reviewing the plan/cost.
```

Use the intended AWS profile consistently for CLI commands when one is selected.
Protect terraform.tfvars, state, backups and saved plans: the install token and
Grafana password can be stored there even when marked sensitive. Use protected
remote state for shared operation. Generate the Boomi token near runtime install;
it may expire during infrastructure creation and may require replacement after
a failed installation.

Acceptance requires: fresh install; all expected nodes/pods Ready; shared PVC
Bound and writable from runtime nodes; runtime Online in Boomi; attachment and
test process deployment; a real execution creating runner/worker pods and
succeeding; KEDA scale-up and scale-down; node scaling if enabled; repeat plan
without unexpected changes; restart/reschedule persistence; controlled cleanup
in an expendable test account. The install token alone does not configure cloud
creation, environments, attachments or platform quotas; the documented manual
steps remain necessary unless separate Boomi API authentication is introduced.

## Validation performed here

Repository contents were retrieved through the authenticated GitHub connector.
Manual cross-file inspection and local diff checks were performed. Terraform,
Helm and an HCL parser were unavailable. The workspace proxy failed; a subsequent
network check stalled and was cancelled. Consequently terraform init/validate,
provider schema checks, chart pulls/renders and live AWS/Boomi tests were not run.
Changes are a reviewable local patch, not a certified release or merged changes.

## Primary references

- [EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [EKS AMI transition guidance](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)
- [Boomi runtime cloud chart](https://hub.docker.com/r/boomi/runtime-cloud)
- [Boomi elastic controller chart](https://hub.docker.com/r/boomi/runtime-elastic-controller)
- [Boomi installer token API](https://developer.boomi.com/docs/api/platformapi/InstallerToken)
- [Boomi runtime provisioning and configuration](https://developer.boomi.com/docs/APIs/PlatformAPI/Usecases/Configuring_runtimes_through_apis)
