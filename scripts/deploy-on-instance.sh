#!/usr/bin/env bash
# Runs as root through SSM, with a reviewed immutable image as its only argument.
set -Eeuo pipefail
image_ref="${1:?Pass an immutable GHCR image reference}"
expected_revision="${2:?Pass the source commit}"
if [[ ! "$image_ref" =~ ^ghcr\.io/ymkt-95/terraform-cloud-platform-demo@sha256:[a-f0-9]{64}$ ]] ||
   [[ ! "$expected_revision" =~ ^[a-f0-9]{40}$ ]]; then
  echo 'Expected this project image pinned by digest and a full source commit.' >&2
  exit 1
fi
exec 9>/var/lock/terraform-demo-deploy.lock
flock -w 300 9

app=terraform-demo-app
candidate=terraform-demo-candidate
previous=terraform-demo-previous
switched=false
committed=false
rollback() {
  code=$?
  trap - EXIT
  docker rm -f "$candidate" >/dev/null 2>&1 || true
  if [ "$switched" = true ] && [ "$committed" = false ]; then
    docker logs --tail 40 "$app" 2>/dev/null || true
    docker rm -f "$app" >/dev/null 2>&1 || true
    if docker inspect "$previous" >/dev/null 2>&1; then
      docker rename "$previous" "$app"
      docker start "$app" >/dev/null
      echo 'Restored previous container after failed deployment.' >&2
    fi
  fi
  exit "$code"
}
trap rollback EXIT

wait_for_release() {
  local url="$1"
  for attempt in {1..30}; do
    if curl -fsS --max-time 3 "$url/health" | grep -q '"status":"healthy"' &&
       curl -fsS --max-time 3 "$url/api/info" | grep -q "\"revision\":\"$expected_revision\""; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# Pull and validate before interrupting the running application.
timeout 300 docker pull "$image_ref"
docker rm -f "$candidate" >/dev/null 2>&1 || true
docker run -d --name "$candidate" --memory=256m --cpus=1 \
  --env DEPLOY_REGION=ap-southeast-2 \
  --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1::3000 "$image_ref"
binding=$(docker port "$candidate" 3000/tcp)
wait_for_release "http://127.0.0.1:${binding##*:}"
docker rm -f "$candidate" >/dev/null

docker rm -f "$previous" >/dev/null 2>&1 || true
if docker inspect "$app" >/dev/null 2>&1; then
  docker stop --time 10 "$app" >/dev/null
  if ! docker rename "$app" "$previous"; then
    docker start "$app" >/dev/null
    exit 1
  fi
fi
switched=true
docker run -d --name "$app" --restart unless-stopped --memory=256m --cpus=1 \
  --env DEPLOY_REGION=ap-southeast-2 \
  --log-opt max-size=10m --log-opt max-file=3 -p 80:3000 "$image_ref"
wait_for_release http://127.0.0.1
committed=true
printf 'Deployment healthy: %s (%s)\n' "$image_ref" "$expected_revision"
# Preserve the previous stopped container/image for recovery. No global prune.
