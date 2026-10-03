# 第二阶段：镜像交付与 AWS 部署准备

这一阶段将本地应用接入镜像发布流程，并写出首版 Terraform 配置。AWS 登录、真实 plan、apply、启动脚本验收和 destroy 是后续的独立验收环节，模拟测试不能替代它们。

## 镜像如何交付

本地镜像不能直接被 EC2 读取。手动触发 GitHub Actions 的 **Publish image** 工作流后，它会构建 `linux/amd64` 镜像、运行容器验证，再推送到 GHCR。工作流使用 GitHub 提供的临时 `GITHUB_TOKEN`，无需配置长期 PAT。

镜像名是 `ghcr.io/ymkt-95/terraform-cloud-platform-demo`，标签包含完整 Git commit。部署使用工作流摘要里的 `@sha256:...` 引用，确保拉取指定内容。

首次发布后，在 GitHub 个人主页的 Packages 中进入该包的 Package settings，将可见性设为 Public。源代码仓库公开并不意味着容器包自动公开。包发布后还需要验证匿名拉取；否则 EC2 的 `docker pull` 会失败。

本地可以用一个临时 Docker 配置验证匿名拉取。`IMAGE_REF` 请填真实 digest；保留 Docker Desktop 使用的连接地址，不复制任何登录凭据：

```bash
IMAGE_REF='ghcr.io/ymkt-95/terraform-cloud-platform-demo@sha256:真实摘要'
docker_endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
anonymous_config=$(mktemp -d)
DOCKER_CONFIG="$anonymous_config" docker --host "$docker_endpoint" pull "$IMAGE_REF"
rmdir "$anonymous_config"
```

## Terraform 文件职责

- `providers.tf`：Terraform/AWS provider 版本、region 和统一标签。
- `variables.tf`：配置入口及验证；镜像必须是 GHCR digest，客户端网段必须是 IPv4 CIDR。
- `network.tf`：VPC、子网、Internet Gateway、路由、关联及安全组。公网 HTTP 默认没有放行来源，必须显式传入客户端 CIDR。
- `iam.tf`：EC2 信任角色、SSM 托管策略和实例配置文件。该角色用于实例上的 SSM Agent，不是你运行 Terraform 的身份。
- `main.tf`：Amazon Linux 2023 AMI 查询和 EC2；显式等待出网路由、安全组出站规则及 SSM 策略就绪。
- `templates/user-data.sh.tftpl`：安装 Docker、启用 Docker/SSM、拉取指定镜像、启动容器并检查健康状态。
- `outputs.tf`：实例 ID、公网地址、应用 URL 和 VPC ID。
- `tests/deployment.tftest.hcl`：不访问 AWS 的模拟 plan 测试。

网络暂时保留在根模块。等真实部署成功后，再使用 `moved` blocks 抽取 network module，并确认 plan 没有非预期重建。

## AWS 登录：何时需要你操作

本地构建、发布 GHCR 镜像和模拟验证都不需要 AWS 账号。真实 `terraform plan` 开始查询可用区、AMI 和已有资源时，才需要 AWS 凭据。

对于已有 IAM 用户或可用角色，可以使用支持 `aws login` 的 AWS CLI v2，在你自己的终端中运行：

```bash
aws login --profile terraform-demo
aws sts get-caller-identity --profile terraform-demo
```

首次登录会询问 region；本项目示例选择 Sydney：`ap-southeast-2`。在浏览器中完成登录和 MFA，不要把密码、授权码或 Access Key 发到聊天或写进仓库。

`aws login` 的身份需要 `SignInLocalDevelopmentAccess` 权限。该权限只解决登录；实际 Terraform 部署还需要对应的 EC2/VPC、IAM 角色/实例配置文件及 PassRole、SSM 公共参数读取等权限。若身份权限不足，应按具体报错补充所需权限。

使用现有支持的 profile 时，可以设置 `AWS_PROFILE=terraform-demo`。如果 Terraform provider 不支持该登录缓存，使用 AWS 官方的 credential_process 桥接方式：

```bash
aws configure set credential_process 'aws configure export-credentials --profile terraform-demo --format process' --profile terraform-demo-process
aws configure set region ap-southeast-2 --profile terraform-demo-process
export AWS_PROFILE=terraform-demo-process
aws sts get-caller-identity
```

上面的命令把“如何获取凭据”写入本机 AWS 配置，不把凭据值写入项目。不要直接执行 export-credentials 并将输出发到聊天。

## 第一次真实 plan 与部署

先完成镜像发布和匿名拉取，再复制 `terraform.tfvars.example` 为同目录的 `terraform.tfvars`，替换镜像摘要和你的公网 IPv4 `/32`。示例里的 `203.0.113.10` 是文档地址，不能直接用于访问。

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deployment.tfplan
```

首次部署预计包含 13 个托管资源，实际以 plan 为准。检查登录账户、region、实例类型、HTTP 来源范围、IAM 角色权限以及是否出现意外删除。当前配置会创建 EC2、EBS 和公网 IPv4，不能假定免费。

审阅完成后执行保存的计划：

```bash
terraform -chdir=terraform apply deployment.tfplan
terraform -chdir=terraform output
```

`apply` 成功后，等待启动脚本完成，然后从允许的公网来源请求输出地址的 `/health`。不要只凭 Terraform 的成功消息判断应用已上线。

## 启动失败时如何检查

在 AWS 控制台打开 Systems Manager → Session Manager，选择输出的实例 ID。登录的 IAM 身份也需要开启会话的权限。实例必须成功注册到 SSM；检查实例角色、Agent 和出网连接。

在会话内检查：

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
sudo tail -n 100 /var/log/terraform-demo-bootstrap.log
sudo systemctl status docker amazon-ssm-agent
sudo docker ps -a
sudo docker logs terraform-demo-app
curl --fail http://127.0.0.1/health
```

本机正常、外网失败时，核对当前客户端公网 IP、安全组允许的 CIDR、实例公网 IP 和路由关联。拉取失败时，检查镜像可见性、digest 和网络。

## 更新、重启和清理

Linux user data 默认首次启动时执行。这里配置 `user_data_replace_on_change = true`，修改镜像或启动脚本会让 Terraform 替换实例。这个无状态演示允许短暂中断；公网地址可能变化。Docker 的 `unless-stopped` 策略用于普通宿主机重启后的容器恢复。

部署后先确认重复 plan 没有非预期变更。后续模块迁移需保留 state；最后再执行 `terraform destroy`，确认资源和根磁盘清理。停止 EC2 不等同于删除全部计费资源。

不要提交或删除尚需使用的本地 state。`.terraform.lock.hcl` 应提交；它锁定 provider，不包含 AWS 登录凭据。

## 参考

- [GHCR 使用说明](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [AWS CLI 本机浏览器登录](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [EC2 user data 生命周期](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- [Terraform provider mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
