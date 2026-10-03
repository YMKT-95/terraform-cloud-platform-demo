# Terraform Cloud Platform Demo

A small portfolio project connecting a Dockerised Node.js service with AWS infrastructure managed by Terraform.

Current scope: the application and local Docker setup. AWS infrastructure, image publishing, Terraform modules and GitHub Actions are planned; they are not implemented yet. This project will use the Terraform CLI and does not require HCP Terraform.

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

The responses are `{"service":"terraform-cloud-platform-demo","version":"0.1.0"}` and `{"status":"healthy"}`. Stop the server with Ctrl+C.

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

## Health and shutdown

`GET /health` returns HTTP 200 when the HTTP service is responding. There are no database or external-service dependencies. Docker records the health result; an unhealthy status alone does not automatically restart a container.

The Node process receives termination signals directly and closes its HTTP server, with a five-second shutdown limit.

## Files and next steps

- `app/server.js`: HTTP endpoints, configurable port and shutdown handling.
- `app/package.json` and `app/package-lock.json`: commands and locked dependencies.
- `app/Dockerfile` and `app/.dockerignore`: runtime image and allowed build inputs.
- [First-stage walkthrough](docs/phase-1.md): Chinese explanations and acceptance checks.

Next: publish a versioned image, provision a VPC and EC2 instance, deploy through user data, refactor networking into a module, then add Terraform validation in CI. Cloud deployment and cleanup will be verified before being described as complete.

## References

- [Express installation](https://expressjs.com/en/starter/installing/)
- [Docker Node.js guide](https://docs.docker.com/guides/nodejs/)
