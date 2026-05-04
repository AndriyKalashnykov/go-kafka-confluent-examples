#!/usr/bin/env bash
# E2E harness: brings up a PLAINTEXT Kafka broker + the consumer image via
# docker compose, runs the producer binary (built from Dockerfile.producer)
# as a one-shot job to publish N messages, then asserts the consumer logged
# a matching number of "Consumed event" lines before timing out.
#
# Both producer and consumer are exercised end-to-end through their
# Dockerfiles + producer.Run / consumer.Run loops — no Kafka CLI
# substitution. Validates env-var plumbing, librdkafka linkage, and the
# Dockerfile.producer build.
#
# Exit codes: 0 pass, non-zero fail. Compose is torn down on exit.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE="docker compose -f docker-compose.e2e.yml"
TOPIC=e2e-topic
N=5
WAIT_TIMEOUT=60

# shellcheck disable=SC2329  # called indirectly via trap
cleanup() {
  echo "==> Tearing down..."
  $COMPOSE --profile producer down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building consumer image + starting broker..."
$COMPOSE up -d --build --wait kafka

echo "==> Creating topic '$TOPIC'..."
docker exec e2e-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --topic "$TOPIC" --partitions 1 --replication-factor 1

echo "==> Starting consumer..."
$COMPOSE up -d consumer
sleep 3  # let the consumer join the group

echo "==> Building producer image and producing $N messages via producer/producer.go binary..."
# `compose run --rm` builds the image (pull_policy: build), starts a one-shot
# container that runs `./producer`, which publishes NUM_MESSAGES events and
# exits. Removes the container after exit.
$COMPOSE --profile producer run --rm \
  -e NUM_MESSAGES="$N" \
  producer

echo "==> Waiting up to ${WAIT_TIMEOUT}s for consumer to process $N messages..."
count=0
for _ in $(seq 1 "$WAIT_TIMEOUT"); do
  count=$($COMPOSE logs consumer 2>/dev/null | grep -c 'Consumed event from topic '"$TOPIC" || true)
  if [ "$count" -ge "$N" ]; then
    echo "PASS: consumer processed $count messages"
    exit 0
  fi
  sleep 1
done

echo "FAIL: consumer processed $count / $N messages"
echo "==> Consumer logs:"
$COMPOSE logs consumer
exit 1
