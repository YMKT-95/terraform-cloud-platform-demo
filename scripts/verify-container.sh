#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:?Usage: bash scripts/verify-container.sh IMAGE}"
container_id=""

cleanup() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null
  fi
}
trap cleanup EXIT

container_id=$(docker run -d -p 127.0.0.1::3000 "$image_ref")
binding=$(docker port "$container_id" 3000/tcp)
host_port="${binding##*:}"

healthy=false
for attempt in {1..30}; do
  status=$(docker inspect --format '{{.State.Health.Status}}' "$container_id")
  if [ "$status" = healthy ]; then
    healthy=true
    break
  fi
  sleep 1
done

if [ "$healthy" != true ]; then
  docker logs "$container_id"
  echo 'Container did not become healthy within 30 seconds' >&2
  exit 1
fi

curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:$host_port/"
curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:$host_port/health" | grep -q '"status":"healthy"'
test "$(docker exec "$container_id" id -u)" != 0

docker stop --time 10 "$container_id" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$container_id")" = 0
docker logs "$container_id" | grep -q 'SIGTERM received'
printf '\nPASS: HTTP endpoints, Docker health, non-root user and graceful shutdown\n'
