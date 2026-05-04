#!/usr/bin/env bash
# E2E harness (KinD flow): spins up a throwaway KinD cluster, deploys an
# in-cluster Kafka broker + the real consumer manifests from k8s/ (with
# PLAINTEXT overrides from e2e/k8s/), produces N messages, asserts the
# consumer pod logs a matching number of "Consumed event" lines, and
# deletes the cluster on exit.
#
# Covers wiring the compose flow can't: Service DNS resolution between
# pods, ConfigMap volume mount at /app, Secret env-var injection, pod
# readiness, Deployment rollout. Loads a locally-built consumer image
# into the KinD node via `kind load docker-image` (imagePullPolicy:
# IfNotPresent so the loaded image takes precedence over ghcr.io).
#
# Prereqs: kind, kubectl, docker. Exit codes: 0 pass, non-zero fail.
set -euo pipefail

CLUSTER=kafka-e2e
NS=kafka-confluent-examples
IMG=kafka-confluent-go-consumer:e2e
TOPIC=e2e-topic
N=5
WAIT_TIMEOUT=90

# Pin kubectl to this cluster's context. A sibling project running
# `kubectl config use-context` against the shared ~/.kube/config could
# otherwise overwrite the current-context globally and have our calls
# hit the wrong cluster (silent failure: namespaces "vanish", rollouts
# wait on non-existent Deployments). See /makefile §"Multi-session
# kubectl context safety".
KUBECTL=(kubectl --context="kind-${CLUSTER}")

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# shellcheck disable=SC2329  # called indirectly via trap
cleanup() {
  echo "==> Deleting KinD cluster $CLUSTER..."
  kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building consumer image: $IMG..."
docker build -f Dockerfile.consumer -t "$IMG" .

echo "==> Creating KinD cluster: $CLUSTER..."
kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER" --wait 120s

echo "==> Loading consumer image into cluster..."
kind load docker-image --name "$CLUSTER" "$IMG"
# The broker image (apache/kafka) is pulled on-demand by the kubelet —
# preloading via `kind load docker-image` fails because the local docker
# image is single-platform but `kind load` exports with --all-platforms
# and hits "content digest not found".

echo "==> Deploying namespace + Kafka broker..."
"${KUBECTL[@]}" apply -f k8s/ns.yaml
"${KUBECTL[@]}" -n "$NS" apply -f e2e/k8s/kafka.yaml

echo "==> Waiting for Kafka rollout (includes first-time docker.io pull of apache/kafka)..."
# docker.io anonymous pull-rate-limit + transient registry hiccups make this
# the most fragile step in the whole harness. Retry the rollout-status wait
# up to 3x with a diagnostic dump on each failure so a flaky pull doesn't
# fail the entire CI run; only escalate on persistent failure.
ROLLOUT_OK=0
for attempt in 1 2 3; do
  if "${KUBECTL[@]}" -n "$NS" rollout status deployment/kafka --timeout=180s; then
    ROLLOUT_OK=1
    break
  fi
  echo "==> Kafka rollout attempt ${attempt}/3 timed out — dumping pod state and retrying..."
  "${KUBECTL[@]}" -n "$NS" get pods -l app=kafka -o wide || true
  "${KUBECTL[@]}" -n "$NS" describe deployment/kafka | tail -40 || true
  "${KUBECTL[@]}" -n "$NS" describe pod -l app=kafka | grep -A3 'Events:' || true
done
if [ "$ROLLOUT_OK" -ne 1 ]; then
  echo "FAIL: Kafka deployment did not become ready after 3 rollout attempts (~9 min)"
  "${KUBECTL[@]}" -n "$NS" logs deployment/kafka --all-containers --tail=100 || true
  exit 1
fi

echo "==> Creating topic '$TOPIC'..."
"${KUBECTL[@]}" -n "$NS" exec deployment/kafka -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic "$TOPIC" --partitions 1 --replication-factor 1

echo "==> Deploying consumer (ConfigMap + Secret + Deployment + Service)..."
"${KUBECTL[@]}" -n "$NS" apply -f e2e/k8s/cm.yaml
"${KUBECTL[@]}" -n "$NS" apply -f e2e/k8s/sc.yaml
"${KUBECTL[@]}" -n "$NS" apply -f e2e/k8s/deployment.yaml
"${KUBECTL[@]}" -n "$NS" apply -f k8s/service.yaml

echo "==> Waiting for consumer rollout..."
"${KUBECTL[@]}" -n "$NS" rollout status deployment/kafka-confluent-go-consumer --timeout=120s
sleep 3  # let the consumer-group join settle

echo "==> Producing $N messages into $TOPIC..."
{
  for i in $(seq 1 "$N"); do
    printf 'e2e-key-%d:e2e-value-%d\n' "$i" "$i"
  done
} | "${KUBECTL[@]}" -n "$NS" exec -i deployment/kafka -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic "$TOPIC" \
  --property parse.key=true --property key.separator=:

echo "==> Waiting up to ${WAIT_TIMEOUT}s for consumer to process $N messages..."
count=0
for _ in $(seq 1 "$WAIT_TIMEOUT"); do
  count=$("${KUBECTL[@]}" -n "$NS" logs deployment/kafka-confluent-go-consumer 2>/dev/null \
    | grep -c 'Consumed event from topic '"$TOPIC" || true)
  if [ "$count" -ge "$N" ]; then
    echo "PASS: consumer processed $count messages"
    exit 0
  fi
  sleep 1
done

echo "FAIL: consumer processed $count / $N messages"
echo "==> Consumer logs:"
"${KUBECTL[@]}" -n "$NS" logs deployment/kafka-confluent-go-consumer || true
echo "==> Kafka logs (tail):"
"${KUBECTL[@]}" -n "$NS" logs deployment/kafka --tail=50 || true
exit 1
