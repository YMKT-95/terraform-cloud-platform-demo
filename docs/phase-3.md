# 第三阶段：Showcase 与持续部署

## 展示页

`/` 现在返回响应式 HTML 页面。`/health` 保留 JSON 健康检查，`/api/info` 返回版本、构建时写入的源代码 commit 与运行区域。页面的状态、响应时间和版本从这些接口读取，响应时间是浏览器发起请求的耗时。

源文件位于 `app/public/`。本地预览：`node app/server.js`，打开 `http://localhost:3000`。本地 revision/region 显示 local；工作流构建镜像时设置 `APP_REVISION`，部署脚本设置运行区域。

## CI/CD 路径

推送 `main` 或手动运行 **Ship showcase**：

1. 调用 **Validate**：Terraform 格式、初始化、配置检查和模拟测试；容器 HTTP、静态资源、健康、非 root 与退出检查；部署脚本的故障注入测试。
2. 构建 AMD64 镜像，写入源代码 SHA。验收后推送 GHCR，并确认匿名拉取成功。
3. 使用 OIDC 交换 AWS 临时凭据，不保存长期 Access Key。
4. 将固定 digest 交给 SSM `AWS-RunShellScript`。实例先拉取镜像并在临时端口验收候选容器，再停止并保留旧容器，启动新版并检查健康和 revision。切换失败时尝试恢复旧容器，工作流仍报告失败。
5. 等待 SSM 命令真正结束；成功后在工作流摘要记录 commit 和 digest。

PR 只做验证，不发布或部署。发布任务依赖验证成功。整个发布工作流串行执行，不中断正在部署的版本；实例上的 `flock` 进一步防止重叠。单实例切换有短暂中断，不是零停机部署。

GitHub runner 通过 SSM 验收实例本机接口，因此无需为 runner IP 开放 HTTP 或 SSH。浏览器从外部访问仍受 Terraform 安全组控制。

## AWS 管理员一次性配置

当前本地 Terraform 用户不能创建 OIDC provider 或给部署角色写入内联策略，需管理员操作。

1. **IAM → Identity providers → Add provider → OpenID Connect**。Provider URL 为 `https://token.actions.githubusercontent.com`，Audience 为 `sts.amazonaws.com`。已有相同 provider 时复用。
2. **IAM → Roles → Create role → Custom trust policy**，复制 [github-deploy-trust.json](iam/github-deploy-trust.json) 全文。跳过附加权限策略，角色名为 `terraform-demo-github-deploy`。
3. 打开新角色 → **Permissions → Add permissions → Create inline policy → JSON**，复制 [github-deploy-permissions.json](iam/github-deploy-permissions.json)，名称为 `TerraformDemoDeploy`。

本仓库启用了 GitHub immutable OIDC subject，实际 API 查询结果包含 owner ID 和 repository ID。信任策略仅允许该仓库 `main` 分支，不能照抄旧版不带 ID 的 `sub` 示例。本工作流不设置 GitHub environment；若以后添加，需要同步更新信任 subject。

部署权限允许通过 AWS-RunShellScript 在当前单台演示实例上执行 root 命令，并读取命令结果。这是对该实例的管理权限；仅应允许受信任维护者修改 main 和工作流。实例角色仍然只使用原先的 SSM Core 策略。

角色创建后设置 GitHub repository **Variables**（不是 Secrets）：

```bash
gh variable set AWS_ROLE_ARN --body 'arn:aws:iam::828874705787:role/terraform-demo-github-deploy'
gh variable set EC2_INSTANCE_ID --body 'i-071cd75e3e74ac7b1'
gh workflow run publish-image.yml --ref main
```

未设置 `AWS_ROLE_ARN` 时 deploy job 会跳过，仅验证和发布镜像；不能把此时的绿色工作流当作部署完成。正式验收要看到 deploy job 成功，并确认公网 `/api/info` 的 revision 与工作流 SHA 一致。

## Terraform 与应用版本的职责

Terraform 继续管理 VPC、EC2、IAM 和安全组，state 保留在本机。CD 只更新现有实例里的容器，不运行 Terraform，不上传本地 state。

`image_ref` 目前仍是**新实例首次启动时的 bootstrap 镜像**。SSM 发布不会改写 Terraform 的 user data 或触发实例替换。后续 Terraform 替换/重建 EC2 时，应审阅 bootstrap 镜像、更新部署权限中的实例 ARN 和 GitHub `EC2_INSTANCE_ID`，然后重新运行 Ship showcase。否则新机器只会运行 bootstrap 版本。计划中的零变更只验证基础设施配置，不能验证容器版本。

已停止的上一版容器保留用于恢复，Docker `unless-stopped` 只重启当前容器。多次发布会积累旧镜像，需要按实际使用情况清理；脚本不执行全局 prune，以免误删无关内容。

## 练习方式

修改 `app/public/index.html` 中的一句介绍，提交并推送 main。观察 Actions 的 validate → publish → deploy，再刷新页面检查 Revision 链接是否指向本次 commit。

此演示使用 HTTP，没有域名/TLS、负载均衡或高可用。对外展示时可将本地 `allowed_http_cidr` 改为 `0.0.0.0/0`，审阅并 apply 只修改 HTTP 入站规则的计划；演示结束后收回访问或清理资源。

## 验证记录

- 本地 AMD64 镜像通过首页、CSS、版本接口、健康、非 root 用户与 SIGTERM 退出验收。
- 本地浏览器已确认页面与实时健康查询可用。
- 部署脚本的故障注入覆盖：候选失败不影响旧服务、切换失败恢复旧服务、成功保留上一版本、拒绝可变镜像标签。模拟测试不替代实际 SSM 发布验收。
- 2026-10-07：首次完整远程 CI/CD 验收成功。[Ship showcase 第 4 次尝试](https://github.com/YMKT-95/terraform-cloud-platform-demo/actions/runs/37365003260/attempts/4) 的三项验证、publish 与 deploy 全部通过。前三次尝试因 GitHub hosted runner 分配故障未完成，恢复后仅重跑未成功的任务。
- 本次发布源代码为 `5a9e6f82ae0e0344de04d975265c1529790e09fe`，应用版本为 `0.2.0`，镜像为 `ghcr.io/ymkt-95/terraform-cloud-platform-demo@sha256:b1fc86e116671002ea10bf74fc13dcca48e373461b2a44f5681a31dc896f42ff`。
- publish 用时 41 秒；deploy 通过 OIDC 登录并经 SSM 完成容器更新，命令成功退出，日志确认健康与运行 revision 匹配。
- 公网验收确认首页已返回展示页，`/health` 与 `/api/info` 均为 HTTP 200，运行 revision 与上述源代码提交一致。当前地址为 `http://32.236.240.144`，仍只允许配置的客户端 IP 访问；实例重建后地址可能变化。
- 这次验证了成功发布路径；真实 AWS 上的失败回滚演练仍未执行，不能将模拟恢复测试描述为线上故障演练。

## 参考

- [GitHub OIDC 与 AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [GitHub immutable subject](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)
- [SSM SendCommand](https://docs.aws.amazon.com/cli/latest/reference/ssm/send-command.html)
