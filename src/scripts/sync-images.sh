#!/usr/bin/env bash
# 将调度器与示例应用镜像同步到 SWR 内网仓库，使集群节点无需公网出口即可拉取。
#
# 前置条件：
#   1. 本机已安装 docker / podman，且可推送至 SWR。
#   2. 已通过 infra 创建 SWR 组织（默认 custom-scheduler）及相应仓库。
#   3. 已按 SWR 控制台「登录指令」完成 docker login（组织名@AK / token）。
#
# 用法：
#   SWR_REGION=cn-north-4 SWR_ORG=custom-scheduler ./sync-images.sh
#
# 环境变量（均可选，含默认值）：
#   SWR_REGION  区域，默认 cn-north-4
#   SWR_ORG     镜像组织名，默认 custom-scheduler
#   VERSIONS    需同步的 kube-scheduler 版本列表（空格分隔）

set -euo pipefail

SWR_REGION="${SWR_REGION:-cn-north-4}"
SWR_ORG="${SWR_ORG:-custom-scheduler}"
SWR_DOMAIN="swr.${SWR_REGION}.myhuaweicloud.com"
VERSIONS="${VERSIONS:-v1.24.17 v1.29.14}"

echo "==> 目标 SWR 内网域名：${SWR_DOMAIN}/${SWR_ORG}"
echo "==> 请先按 SWR 控制台「登录指令」完成 docker login（组织名@AK / token），再继续。"
read -r -p "已完成登录？(y/N) " ok
[ "${ok:-N}" = "y" ] || { echo "已取消。"; exit 1; }

sync_one() {
  local src="$1" dst="$2"
  echo "==> pull  ${src}"
  docker pull "${src}"
  echo "==> tag   ${src} -> ${dst}"
  docker tag "${src}" "${dst}"
  echo "==> push  ${dst}"
  docker push "${dst}"
}

# 调度器标准镜像（公开仓库 -> SWR 内网）
for v in ${VERSIONS}; do
  sync_one "registry.k8s.io/kube-scheduler:${v}" \
           "${SWR_DOMAIN}/${SWR_ORG}/kube-scheduler:${v}"
done

# 示例应用 Web 服务器镜像（公开仓库 -> SWR 内网）
sync_one "nginx:stable-perl" \
         "${SWR_DOMAIN}/${SWR_ORG}/nginx:stable-perl"

echo "==> 同步完成。节点现可经 SWR 内网拉取上述镜像，无需公网出口。"
