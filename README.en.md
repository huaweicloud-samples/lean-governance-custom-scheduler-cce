# Custom Kubernetes Scheduler with Bin-Packing — Huawei Cloud Practice

[![License: MIT-0](https://img.shields.io/badge/License-MIT--0-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-CCE-red.svg)](https://support.huaweicloud.com/intl/en-us/)

> Deploy a custom Kubernetes scheduler with the MostAllocated bin-packing score strategy on Huawei Cloud Container Engine (CCE).
> This is a migrated, cloud-neutral reference architecture derived from a public sample.

---

## 1. Overview

This reference architecture runs a custom Kubernetes scheduler on CCE with the `MostAllocated` bin-packing score strategy, improving node utilization and reducing fragmentation for batch and short-lived workloads. It targets DevOps engineers, platform operators, and backend developers as a reference architecture or production template.

### Core Capabilities

- Run a second scheduler alongside the default scheduler on a managed Kubernetes cluster, without affecting default scheduling behavior
- Enable the `MostAllocated` strategy of `NodeResourcesFit` via `KubeSchedulerConfiguration`
- Business Pods explicitly select the custom scheduler through `spec.schedulerName`
- Two delivery forms: a Helm chart and static manifests, plus optional monitoring configuration

---

## 2. Directory

- [1. Overview](#1-overview)
- [2. Directory](#2-directory)
- [3. Architecture](#3-architecture)
- [4. Highlights](#4-highlights)
- [5. Cloud Services](#5-cloud-services)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Details](#11-details)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact](#16-contact)
- [17. Creator / Maintainer](#17-creator--maintainer)

---

## 3. Architecture

> Within a CCE cluster, run the custom scheduler as an independent Deployment; business Pods explicitly select it.

```mermaid
flowchart LR
    subgraph Network[Network Layer]
        VPC[VPC / Subnet]
        NAT[NAT Gateway + EIP (optional)]
    end
    subgraph CCE[Container Engine Cluster]
        CP[Cluster Control Plane]
        NP[Node Pool]
        SCHED[Custom Scheduler]
        APP[Sample Application]
    end
    SWR[SWR Internal Image Registry]
    NP --> SWR
    NAT -.enable_nat=true.-> EXT[Public Standard Image]
    SCHED --> CP
    APP --> SCHED
```

**Key components**:

- **CCE**: Managed Kubernetes cluster providing the control plane and node pool
- **Custom Scheduler**: A second `kube-scheduler` instance enabling the MostAllocated bin-packing strategy
- **SWR**: Container image registry; by default images are pulled over the internal network, so nodes need no public egress
- **Public egress (optional)**: Created only when `enable_nat=true`, used for nodes to pull images over the public network

---

## 4. Highlights

- **Higher node utilization**: The MostAllocated strategy fills nodes with higher used-resource ratios first, reducing fragmentation
- **Non-invasive to workloads**: Only a `schedulerName` is needed on the Pod; default cluster scheduling is unaffected
- **High availability**: Multiple replicas + leaderElection avoid a single point of failure
- **Dual delivery forms**: Helm chart and static manifests to suit different delivery preferences

---

## 5. Cloud Services

| Service | Purpose | Notes |
|---|---|---|
| Cloud Container Engine (CCE) | Managed Kubernetes cluster | Runs the scheduler and workloads |
| Virtual Private Cloud (VPC) | Network isolation and subnet planning | Network for cluster and nodes |
| NAT Gateway + EIP (optional) | Node public egress | Created only when `enable_nat=true`, for public image pulls |
| Security Group | Node network access control | Node egress and intra-group access |
| Container Registry (SWR) | Hosts scheduler and sample images | Pulled over internal network by default |

---

## 6. Prerequisites

| Item | Requirement | Description |
|---|---|---|
| Account | Huawei Cloud account with real-name verification | Personal or enterprise accounts are both fine |
| Permissions | Create permissions for VPC / CCE / SWR, etc. (add NAT if public egress is needed) | Tenant Administrator or equivalent is recommended |
| Region | `cn-north-4` recommended | Must match node flavor and image availability |
| Tools | Terraform `>= 1.5.0`, kubectl (matching cluster version), Helm `>= 3.0` (optional) | kubectl version must match the cluster Kubernetes version |
| Credentials | Access Key (AK/SK) | Provided at runtime via environment variables, never written to files |

---

## 7. Quick Start

```bash
# 1. Configure access credentials (never written to any file)
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 2. Orchestrate the cloud base
cd infra
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -auto-approve
cd ..

# 3. Fetch the CCE kubeconfig and point it locally
export KUBECONFIG=/path/to/your/kubeconfig
kubectl get nodes

# 3.5 Sync images to the SWR internal registry (no public egress needed by default; run after apply)
bash src/scripts/sync-images.sh

# 4. Deploy the custom scheduler (Kubernetes 1.25+ manifests)
kubectl apply -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml

# 5. Deploy the sample application (uses the custom scheduler)
kubectl apply -f src/deployments/nginx-deployment.yaml
```

---

## 8. Step-by-Step Deployment

1. **Orchestrate the base**: In `infra/`, run `terraform init → plan → apply` to create VPC, subnets, security group, CCE cluster and node pool, and SWR (no NAT by default; set `infra` variable `enable_nat=true` for node public egress).
2. **Acquire credentials**: Obtain the CCE kubeconfig via the console or CLI and configure local kubectl.
3. **Deploy the scheduler**:
   - Static manifests: `kubectl apply -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml` (1.25+); for 1.24 use `cce-custom-scheduler-1.24.yaml`.
   - Or Helm: `helm install custom-scheduler ./src/helm/custom-scheduler --namespace kube-system --set k8sVersion=1.29`.
4. **Deploy the sample app**: `kubectl apply -f src/deployments/nginx-deployment.yaml`.
5. **Optional monitoring**: `kubectl apply -f src/manifests/monitoring/`.

---

## 9. Usage / Verification

### Verification 1: Scheduler components are running

```bash
kubectl get pods -n kube-system -l component=scheduler,tier=control-plane
```

**Expected**: 2 Pods in `Running` state.

### Verification 2: The sample app is taken over by the custom scheduler

```bash
kubectl get pods -n nginx-test -o wide
kubectl get pod -n nginx-test <pod-name> -o jsonpath='{.spec.schedulerName}'
```

**Expected**: Pod is `Running` and `schedulerName` is `custom-k8s-scheduler`.

### Verification 3: Observe the bin-packing effect

```bash
kubectl top nodes
kubectl describe pod -n nginx-test <pod-name> | grep -A2 Scheduler
```

**Expected**: Pods land on nodes with higher allocated resources, showing bin-packing characteristics.

---

## 10. Cleanup

```bash
# Release workloads
kubectl delete -f src/deployments/nginx-deployment.yaml
kubectl delete -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml

# Release the cloud base
cd infra && terraform destroy -auto-approve
```

---

## 11. Details

### Workflow

A business Pod specifies the custom scheduler name in `spec.schedulerName` → that scheduler instance selects a node for the Pod based on the `MostAllocated` strategy in `KubeSchedulerConfiguration` → node resources concentrate on high-occupancy nodes, improving single-node utilization.

### Configuration (Terraform variables)

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Deployment region |
| `project_name` | `custom-scheduler` | Resource naming prefix |
| `node_flavor` | `s6.large.2` | Node pool compute flavor |
| `node_count` | `2` (set `1` for verification) | Initial node count of the node pool |
| `swr_organization` | `custom-scheduler` | Image organization name |
| `enable_nat` | `false` | Whether to create a NAT gateway + EIP for node public egress |
| `eip_bandwidth_size` | `5` | Effective only when enable_nat=true: NAT egress bandwidth (Mbit/s) |

### Configuration (Helm variables)

| Variable | Default | Description |
|---|---|---|
| `k8sVersion` | `1.29` | Derives the scheduler image tag |
| `schedulerName` | `custom-k8s-scheduler` | Scheduler name referenced by Pods |
| `replicaCount` | `2` | Scheduler replica count |
| `monitoring.enabled` | `false` | Whether to create the metrics Service / ServiceMonitor |

---

## 12. Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5.0` | Infrastructure orchestration |
| huaweicloud Provider | `>= 1.96.0` | Huawei Cloud resources |
| Helm | `>= 3.0` | Chart delivery (optional) |
| kubectl | Matching cluster version | Manifest delivery and verification |

---

## 13. FAQ / Troubleshooting

### Q1: "Insufficient permissions" during deployment?

**A**: Confirm the account has create permissions for VPC, CCE, SWR, NAT, etc., or at least the corresponding sub-service administrator permissions.

### Q2: The sample app is not taken over by the custom scheduler?

**A**: Check whether the Pod's `spec.schedulerName` is set to `custom-k8s-scheduler` and the scheduler Pod is `Running`. If the scheduler is not ready, the Pod will be `Pending`.

### Q3: Node fails to pull the image?

**A**: By default, images are pulled from the SWR internal registry over the internal network, requiring no public network. If it fails, verify the image address is `swr.<region>.myhuaweicloud.com/<organization>/...` and the SWR repository has the corresponding tag; run `src/scripts/sync-images.sh` to re-sync. If public pull is truly needed, set `enable_nat=true` and ensure the node security group egress allows public access.

### Troubleshooting checklist

| Symptom | Possible cause | Troubleshooting |
|---|---|---|
| Scheduler Pod `Pending` | Insufficient node resources / security group restriction | `kubectl describe pod` to view events |
| Business Pod not scheduled | `schedulerName` typo | Verify Pod and scheduler names |
| Image pull failure | Wrong SWR internal address or missing tag | Verify image address and sync-images.sh result |

---

## 14. Contributing

Issues and PRs are welcome. Please follow this flow:

1. **Issue**: Describe the problem / suggestion (with reproduction commands, expected / actual output).
2. **PR**: Create a feature branch from `main`; run `terraform validate` and gate checks before submitting.
3. **Code Review**: Reviewed and merged by a maintainer.

---

## 15. License

This practice is released under the **MIT No Attribution** license. See the [`LICENSE`](LICENSE) file at the repository root.

---

## 16. Contact

| Item | Content |
|---|---|
| Contact | Feedback via repository Issues |

---

## 17. Creator / Maintainer

| Role | Account |
|-|-|
| **Creator** | zhangcheng123321 |
| **Maintainer** | zhangcheng123321 |
