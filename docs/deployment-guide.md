# 部署指导（Deployment Guide）

> 本指南说明如何在本仓库的云上底座之上，部署自定义调度器与示例应用。
> 全流程分为：准备凭据与工具、编排底座（Terraform）、部署调度器、部署示例应用、验证。

---

## 1. 前置准备

| 项 | 要求 |
|---|---|
| 账号 | 已开通华为云账号并完成实名认证 |
| 权限 | 具备 VPC、CCE、SWR、NAT 等服务的创建权限（建议 Tenant Administrator 或等效） |
| 工具 | Terraform `>= 1.5.0`、kubectl（与集群版本匹配）、Helm `>= 3.0`（可选） |
| 凭据 | 访问密钥（AK/SK），运行时经环境变量提供，不写入文件 |

```bash
export HW_ACCESS_KEY="<你的访问密钥>"
export HW_SECRET_KEY="<你的私密密钥>"
```

---

## 2. 编排云上底座

进入 `infra/` 目录，初始化并预览：

```bash
cd infra
# 复制变量示例并按需修改
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply -auto-approve
```

执行完成后，记录输出的集群信息（kubeconfig 获取方式、节点池、SWR 组织名）。

获取集群访问凭证并配置 kubectl：

```bash
# 通过控制台或命令行获取 CCE kubeconfig 后，指向本地
export KUBECONFIG=/path/to/your/kubeconfig
kubectl get nodes
```

---

## 3. 部署自定义调度器

### 方式一：静态清单（推荐先验证）

选择与集群 Kubernetes 版本匹配的清单：

- Kubernetes 1.25+：`src/manifests/custom-scheduler/cce-custom-scheduler.yaml`
- Kubernetes 1.24：`src/manifests/custom-scheduler/cce-custom-scheduler-1.24.yaml`

```bash
kubectl apply -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml
```

### 方式二：Helm 图表

```bash
helm install custom-scheduler ./src/helm/custom-scheduler \
  --namespace kube-system \
  --set k8sVersion=1.29 \
  --set schedulerName=custom-k8s-scheduler
```

> 镜像 tag 由 `k8sVersion` 自动推导；如需手动指定，设置 `--set image.tag=v1.29.14`。

---

## 4. 部署示例应用

示例应用通过 `spec.schedulerName: custom-k8s-scheduler` 显式选择自定义调度器：

```bash
kubectl apply -f src/deployments/nginx-deployment.yaml
```

---

## 5. 可选：开启监控

如集群已部署 Prometheus Operator / 云原生监控，可创建指标 Service 与 ServiceMonitor：

```bash
kubectl apply -f src/manifests/monitoring/custom-scheduler-metrics-svc.yaml
kubectl apply -f src/manifests/monitoring/custom-scheduler-servicemonitor.yaml
```

---

## 6. 验证

### 验证 1：调度器组件运行正常

```bash
kubectl get pods -n kube-system -l component=scheduler,tier=control-plane
```

**预期**：2 个 Pod 处于 `Running` 状态。

### 验证 2：示例应用被自定义调度器接管

```bash
kubectl get pods -n nginx-test -o wide
kubectl get pod -n nginx-test <pod-name> -o jsonpath='{.spec.schedulerName}'
```

**预期**：Pod 处于 `Running`，且 `schedulerName` 为 `custom-k8s-scheduler`。

### 验证 3：装箱效果观察

通过节点资源视图观察 Pod 是否向少数节点聚集（提升单节点利用率）：

```bash
kubectl top nodes
kubectl describe pod -n nginx-test <pod-name> | grep -A2 Scheduler
```

**预期**：Pod 落在已分配资源较高的节点，呈现装箱（bin-packing）特征。

---

## 7. 清理

```bash
kubectl delete -f src/deployments/nginx-deployment.yaml
kubectl delete -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml
cd infra && terraform destroy -auto-approve
```

---

## 8. 验证专用最小化执行清单（凭据仅经环境变量提供，不落盘）

> 面向「在云上实跑一次验证」的最小配置：`infra/terraform.tfvars.example` 中 `node_count = 1`、`enable_nat = false`，节点经 SWR 内网拉取镜像，无需创建 NAT 公网出口。
> 验证通常几十分钟内即可完成，确认结果后立即执行 destroy，无需长时间保留资源（按量资源按实际占机时长结算）。
> **凭据（访问密钥、SWR 登录密钥）全程只存在于当前 shell 的环境变量，绝不写入任何 `.tfvars`、脚本或报告**；全部步骤结束执行 `unset` 即可清除。

### 步骤 0 — 配置访问凭据（每个新 shell 都需执行；仅内存，不落盘）

```bash
# 云访问密钥（huaweicloud provider 直接读取以下变量）
export HW_ACCESS_KEY="<你的访问密钥 AK>"
export HW_SECRET_KEY="<你的私密密钥 SK>"
export HW_REGION_NAME="cn-north-4"

# 镜像仓库登录凭据（用于 docker 登录 SWR 内网）
export SWR_LOGIN_USER="<你的 IAM 用户名>"
export SWR_LOGIN_PASSWORD="<SWR 登录密钥（控制台获取）>"
```

> 切勿将以上取值粘贴进任何文件。`terraform apply` / `docker push` 完成后用
> `unset HW_ACCESS_KEY HW_SECRET_KEY HW_REGION_NAME SWR_LOGIN_USER SWR_LOGIN_PASSWORD` 清除。

### 步骤 1 — 编排底座（terraform init / plan / apply）

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # 已含 node_count=1、enable_nat=false
terraform init
terraform plan
terraform apply -auto-approve     # 将实际创建云上资源，请先确认规格无误
```

### 步骤 2 — 同步镜像到 SWR 内网（仅首次，节点需内网拉取）

在有公网访问能力、且已安装 docker 的机器上执行：

```bash
# 登录 SWR 内网镜像仓库
docker login -u "$SWR_LOGIN_USER" -p "$SWR_LOGIN_PASSWORD" swr.cn-north-4.myhuaweicloud.com

# 一键同步 kube-scheduler 与 nginx 到 SWR 内网（脚本内部仅用环境变量，无硬编码）
bash src/scripts/sync-images.sh
```

> 同步完成后，集群节点即可经内网域名拉取镜像，无需 NAT 公网出口。

### 步骤 3 — 获取集群访问凭证并验证

```bash
# 通过控制台或命令行获取 CCE kubeconfig，指向本地
export KUBECONFIG=/path/to/your/kubeconfig
kubectl get nodes

# 部署自定义调度器（按集群版本选择清单）
kubectl apply -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml

# 部署示例应用（显式选择自定义调度器）
kubectl apply -f src/deployments/nginx-deployment.yaml
```

验证要点（详见第 6 节）：
- `kubectl get pods -n kube-system -l component=scheduler,tier=control-plane` → 2 个 Running
- `kubectl get pods -n nginx-test -o wide` 且 Pod 的 `schedulerName` 为 `custom-k8s-scheduler`
- `kubectl top nodes` 观察装箱聚集效果

### 步骤 4 — 清理（务必执行，否则资源持续占用）

```bash
kubectl delete -f src/deployments/nginx-deployment.yaml
kubectl delete -f src/manifests/custom-scheduler/cce-custom-scheduler.yaml
cd infra && terraform destroy -auto-approve
unset HW_ACCESS_KEY HW_SECRET_KEY HW_REGION_NAME SWR_LOGIN_USER SWR_LOGIN_PASSWORD
```
