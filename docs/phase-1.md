# 第一阶段：应用与 Docker

这一阶段先验证代码能在本机和容器中运行，为后续 EC2 部署准备一个可用的应用。尚未创建 AWS 资源。

## 文件如何配合

`app/server.js` 创建 Express 服务，提供 `/` 和 `/health`。`PORT` 默认是 3000，监听 `0.0.0.0`，让容器能接收外部转发来的请求。收到 SIGTERM 或 Ctrl+C 时关闭 HTTP 服务。

`app/package.json` 声明 Node.js 版本、Express 依赖以及启动命令。`package-lock.json` 锁定依赖树；后续使用 `npm ci` 按锁文件安装。

`app/Dockerfile` 依次准备 Node.js 环境、安装依赖、复制代码、切换到非 root 用户并启动服务。先复制依赖清单可以让只修改业务代码的构建复用依赖层。当前没有编译步骤，因此无需多阶段构建。

`app/.dockerignore` 只允许服务代码和依赖清单进入构建上下文，避免将本机依赖和环境文件打包进去。根目录 `.gitignore` 保护本地依赖、环境文件及未来的 Terraform state、变量和 plan 文件；`.terraform.lock.hcl` 应提交。

## 运行与验收

在项目根目录执行 `cd app`、`npm ci`、`npm start`。`npm ci` 安装锁定依赖，`npm start` 启动 HTTP 服务。另开终端执行：

```bash
curl --fail http://localhost:3000/
curl --fail http://localhost:3000/health
```

预期两者均返回 HTTP 200，健康接口内容为 `{"status":"healthy"}`。Ctrl+C 停止应用。

在项目根目录执行：

```bash
docker build -t terraform-demo-app:local ./app
docker run --rm --name terraform-demo-app -p 127.0.0.1:3000:3000 terraform-demo-app:local
```

`build` 用 `app/` 作为构建上下文生成镜像；`run` 创建容器，将本机回环地址的 3000 端口映射到容器的 3000 端口；`--rm` 在容器停止后移除它。再次检查两个接口，然后执行：

```bash
docker inspect --format '{{.State.Health.Status}}' terraform-demo-app
docker stop terraform-demo-app
```

健康状态应在首次探测后变为 `healthy`，停止时应看到服务收到 SIGTERM 的日志。Docker 健康检查只标记状态，本身不会因为 unhealthy 自动重启容器。

## 与后续 Terraform 的连接

本阶段只在本机保存镜像。EC2 不能直接读取本机 Docker 镜像，因此下一步先确定镜像仓库并发布指定版本，然后才让启动脚本拉取它。

本机默认构建跟随主机架构；面向 x86 EC2 时需要明确构建 `linux/amd64`。Terraform 阶段还会单独验证网络、启动日志、应用健康以及资源清理。

## 本轮验证结果

已在本机完成以下检查：

- Node.js 24 本地服务的两个接口均返回 HTTP 200 和预期 JSON。
- 自定义 `PORT` 生效，未知路径返回 404，SIGTERM 退出码为 0。
- Docker 镜像构建成功，容器发布的两个 HTTP 接口返回预期结果。
- Docker 健康状态变为 `healthy`，容器实际用户不是 root。
- `docker stop` 触发 SIGTERM，应用退出码为 0；临时验证容器已移除。

本次 Docker 验证平台为本机的 Linux ARM64 容器环境。尚未验证 AMD64 镜像、镜像仓库发布或 AWS 部署。
