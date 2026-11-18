variable "region" {
  description = "部署区域。建议与镜像、规格可售性一致的区域，如 cn-north-4。"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "核心基础设施统一命名前缀，用于资源命名与标签。"
  type        = string
  default     = "custom-scheduler"
}

variable "vpc_cidr" {
  description = "VPC 网段。"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "公网子网网段（NAT 网关所在）。"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "私网子网网段（容器工作负载落位于此）。"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "swr_organization" {
  description = "容器镜像组织（SoftWare Repository 命名空间），用于托管自定义镜像。"
  type        = string
  default     = "custom-scheduler"
}

variable "node_flavor" {
  description = "节点池计算规格（须为所选区域真实可售规格）。"
  type        = string
  default     = "s6.large.2"
}

variable "node_count" {
  description = "节点池初始节点数。运行期由弹性伸缩改写，故在节点池上配置 ignore_changes。"
  type        = number
  default     = 2
}

variable "node_login_public_key" {
  description = "节点登录公钥（SSH）。留空占位时请替换为自有公钥；不可 SSH 登录请改为密码方式。"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIplaceholder-replace-with-your-own-public-key zhangcheng@localhost"
}

variable "enable_nat" {
  description = "是否创建 NAT 网关 + EIP 提供节点公网出口。默认 false：节点经 SWR 内网拉取镜像，不产生出网费。设为 true 时才会创建 NAT 与 EIP，并参考 eip_bandwidth_size。"
  type        = bool
  default     = false
}

variable "eip_bandwidth_size" {
  description = "仅当 enable_nat=true 时生效：NAT 网关绑定的按需按流量 EIP 带宽大小（Mbit/s）。"
  type        = number
  default     = 5
}
