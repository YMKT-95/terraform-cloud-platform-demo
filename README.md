# Terraform Cloud Platform Demo

A small portfolio project connecting a Dockerised Node.js service with AWS infrastructure managed by Terraform.

Current scope: a live showcase page, a verified Docker image, and a working GitHub Actions delivery pipeline to one Terraform-managed EC2 instance in Sydney. The first real apply created 13 resources and a subsequent plan reported no changes. On 2026-10-07, image publishing and OIDC/SSM deployment passed end to end; public HTTP checks confirmed version 0.2.0 and the expected source revision. See the [successful workflow](https://github.com/YMKT-95/terraform-cloud-platform-demo/actions/runs/37365003260/attempts/4). Cleanup, restart recovery and the networking-module refactor are still pending. This project uses the Terraform CLI and does not require HCP Terraform.

## Run locally

Prerequisites: Node.js 24 and npm. If you use nvm, run `nvm use` from the repository root.

```bash
cd app
npm ci
npm start
```

In another terminal:

```bash
curl --fail http://localhost:3000/
curl --fail http://localhost:3000/health
```

The root path serves the showcase page. `/health` returns `{"status":"healthy"}`; `/api/info` returns the running version, source revision and region. Stop the server with Ctrl+C.

Use `npm run dev` to restart automatically when source files change. Set `PORT=3001 npm start` if port 3000 is already occupied. The server listens on `0.0.0.0` so it can also receive traffic inside a container.

## Run with Docker

Prerequisite: a running Docker engine. From the repository root, after stopping the local server:

```bash
docker build -t terraform-demo-app:local ./app
docker run --rm --name terraform-demo-app -p 127.0.0.1:3000:3000 terraform-demo-app:local
```

In another terminal, run the same curl commands above. After the first health check, inspect the container:

```bash
docker inspect --format '{{.State.Health.Status}}' terraform-demo-app
docker logs terraform-demo-app
docker stop terraform-demo-app
```

The container runs as the non-root `node` user and is removed when it stops. Port publishing is restricted to localhost for local development. `EXPOSE` documents the container port; the `-p` option makes it accessible from the host.

Dependencies are pinned in `package-lock.json` and installed with `npm ci`. The base image follows the Node.js 24 Debian slim tag; its digest is not pinned yet. The build context only includes the application source and dependency manifests.

The default build targets the local machine's architecture. Before deploying to x86 EC2, build and verify a `linux/amd64` image; an Apple Silicon build must not be assumed to work on x86.

```bash
docker build --platform linux/amd64 -t terraform-demo-app:amd64 ./app
bash scripts/verify-container.sh terraform-demo-app:amd64
```

The verification script starts a temporary container, checks published HTTP endpoints, Docker health, the non-root user and graceful shutdown, then removes the container.

## Publish an image

The **Ship showcase** workflow runs on pushes to `main` and manual dispatch. It calls validation, builds and verifies an AMD64 image, then pushes `ghcr.io/ymkt-95/terraform-cloud-platform-demo:sha-<commit>` using its temporary `GITHUB_TOKEN`. When the AWS OIDC role is configured, it deploys the immutable digest to the existing EC2 instance using SSM, verifies the running commit and attempts rollback if cutover fails. See [CI/CD setup and walkthrough](docs/phase-3.md).

A public source repository does not by itself guarantee that its GHCR package is public. Verify the package visibility is **Public**, then verify a pull using a clean Docker credential configuration. EC2 expects anonymous access; no registry token is placed in user data. The first published image is public and its anonymous AMD64 pull has been verified; its digest is recorded in `terraform/terraform.tfvars.example`.

## Terraform configuration

The root configuration in `terraform/` defines one VPC, a public subnet, an internet gateway and route, HTTP security-group rules, an SSM instance role and one EC2 instance. The public subnet is derived from the VPC CIDR. EC2 uses Amazon Linux 2023 x86_64, an encrypted 8 GiB root disk and IMDSv2. Docker publishes container port 3000 on host port 80. HTTP access is restricted by `allowed_http_cidr`; there is no SSH ingress rule.

Terraform's local state is kept outside Git. Keep it until `destroy` has completed; it is required to track and clean up resources. The provider lock file is committed. The current toolchain uses Terraform 1.16.5 and the AWS provider version recorded in that lock file.

Validation without AWS credentials:

```bash
terraform -chdir=terraform init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
```

Tests use a mock AWS provider. They check the intended network/security settings and reject mutable image tags, invalid client CIDRs and incompatible ARM instance types. They do not prove that account permissions, AMI availability or EC2 bootstrap work in AWS.

For a real deployment, authenticate to AWS and use an anonymously accessible image. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, replacing the client address and, when deploying a newer image, the digest. Then:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deployment.tfplan
# Review account, region and every planned change before creating resources.
terraform -chdir=terraform apply deployment.tfplan
terraform -chdir=terraform output
# Wait for bootstrap and check the application's /health endpoint.
terraform -chdir=terraform destroy
```

EC2, EBS and public IPv4 can incur charges. This demo has no load balancer, NAT gateway or database. Apply returning successfully does not mean the container is ready. Use SSM Session Manager to inspect `/var/log/cloud-init-output.log`, `/var/log/terraform-demo-bootstrap.log` and `docker logs terraform-demo-app` if the HTTP check fails.

Changes to Terraform's bootstrap image/user data replace the instance and can change its public address. Routine application releases use SSM to replace only the container. After infrastructure replacement, update the workflow target and its IAM resource scope, then deploy again; Terraform's bootstrap image is not automatically kept in sync with CD. The AMI comes from AWS's current Amazon Linux 2023 public SSM parameter; a later AMI update can also propose replacement. Review every plan. The demo serves plain HTTP and has a single instance; it is not a production deployment.

## Continuous integration

**Validate** runs on pull requests, manual dispatch and as a required job in **Ship showcase**. It checks Terraform formatting, initialization with the committed provider lock file, validation, mocked plans, the AMD64 container and deployment recovery behavior. Validation has no AWS credentials. The release workflow grants package-write permission only to publishing and OIDC permission only to deployment. Deployment is limited to the configured demo instance.

## Health and shutdown

`GET /health` returns HTTP 200 when the HTTP service is responding. There are no database or external-service dependencies. Docker records the health result; an unhealthy status alone does not automatically restart a container.

The Node process receives termination signals directly and closes its HTTP server, with a five-second shutdown limit.

## Files and next steps

- `app/server.js` and `app/public/`: showcase page, live health/release endpoints and shutdown handling.
- [Showcase and CI/CD](docs/phase-3.md): OIDC setup, release flow, rollback and the Terraform/application boundary.
- `app/package.json` and `app/package-lock.json`: commands and locked dependencies.
- `app/Dockerfile` and `app/.dockerignore`: runtime image and allowed build inputs.
- [First-stage walkthrough](docs/phase-1.md): Chinese explanations and acceptance checks.
- [Deployment preparation](docs/phase-2.md): image publishing, Terraform resource responsibilities, AWS login and deployment checks in Chinese.

Next: verify restart recovery and cleanup, then refactor networking into a module using `moved` blocks. The first deployment and application bootstrap are verified; destroy has not yet been tested. See the [deployment verification record](docs/phase-2.md#本轮验证记录) for the completed checks.

## References

- [Express installation](https://expressjs.com/en/starter/installing/)
- [Docker Node.js guide](https://docs.docker.com/guides/nodejs/)
- [Terraform provider mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [GHCR authentication and visibility](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [AWS CLI browser-based login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
