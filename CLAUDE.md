# CLAUDE.md

## Project Overview

Go-based Confluent Kafka Cloud producer/consumer examples using the [confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go/) client, with Kubernetes deployment support and Docker containerization.

## Tech Stack

- **Language**: Go 1.26.2
- **Kafka Client**: confluent-kafka-go v2.14.1 (CGO, `librdkafka`)
- **Build**: Make, GoReleaser (cross-compilation)
- **Container**: Docker, Docker Compose
- **Orchestration**: Kubernetes
- **CI/CD**: GitHub Actions
- **Version manager**: mise (`.mise.toml`, `.nvmrc`) — manages Go, Node, and all host-installed lint/security tools (golangci-lint, gosec, gitleaks, hadolint, trivy, actionlint, shellcheck, govulncheck, act). Note: `node = "24"` is a major-only constraint by design — the renovate-validate target only needs a recent Node 24 line; tightening to a full patch would create churn without value.
- **Static analysis**: golangci-lint, gosec, govulncheck, gitleaks, actionlint, shellcheck, hadolint, trivy (filesystem + K8s misconfigs), mermaid-cli (diagram parse-check)
- **Dependency Management**: Renovate (mise + gomod + dockerfile + docker-compose + kubernetes managers; `automergeType: "pr"` because main has the `ci-pass` required check)

## Project Structure

```
producer/          - Kafka producer entrypoint (thin shell over internal/producer.Run)
consumer/          - Kafka consumer entrypoint (thin shell over internal/consumer.Run)
internal/
  producer/        - Producer Run loop, applyDefaults, produceWithRetry (unit-tested)
  consumer/        - Consumer Run loop, applyDefaults (unit-tested)
  util/            - Env-var → kafka.ConfigMap plumbing (BuildKafkaConfigMap)
  kafkaroundtrip/  - Integration test: real broker via Testcontainers, produces and consumes
k8s/               - Kubernetes manifests (ns, cm, sc, deployment, service)
e2e/               - E2E harness: compose flow + KinD flow + PLAINTEXT fixtures
scripts/           - Setup scripts (cross-compilation, toolchain install, kind/kubectl)
tmpl/              - Template files (.env, kafka.properties, k8s secrets)
.github/workflows/ - CI/CD workflows
```

## Build & Development

```bash
make help           # List all available targets
make build          # Build producer and consumer binaries (output: .bin/)
make test           # Unit tests (fast, no external deps; -race -cover)
make integration-test # Integration tests (Testcontainers-backed, -tags=integration)
make e2e-compose    # E2E via Docker Compose (PLAINTEXT broker + consumer image)
make e2e            # E2E via KinD cluster + in-cluster Kafka + real k8s/ manifests
make format         # Format Go code
make lint           # Run golangci-lint and hadolint
make static-check   # Composite quality gate (format-check + deps-prune-check + lint + lint-ci + sec + vulncheck + secrets + trivy-fs + mermaid-lint)
make ci             # Run all CI checks (static-check, test, build)
make ci-run         # Run GitHub Actions workflow locally via act
make clean          # Remove build artifacts
make deps           # Install and verify required tools (mise + Go)
make deps-check     # Show required Go version and mise status
```

### Environment

- Requires `.env` file for Kafka credentials (see `tmpl/.env.tmpl`)
- Requires `kafka.properties` for Kafka config (see `tmpl/kafka.properties.tmpl`)
- CGO is enabled (required by confluent-kafka-go / librdkafka)
- `NUM_MESSAGES` env var (optional) overrides the producer's default 10-message run; the e2e-compose harness sets this to fix the publish count for assertion-counting

### Test pyramid

- **Unit** (`make test`): tests against `applyDefaults` helpers, `produceWithRetry` (driven by an injected fake `*kafka.Producer`), `BuildKafkaConfigMap`, and broker-unreachable / ctx-cancel guard rails. Runs in seconds, no Docker.
- **Integration** (`make integration-test`): `internal/kafkaroundtrip/roundtrip_integration_test.go` — Apache Kafka 3.9.0 KRaft container via Testcontainers. Three tests: end-to-end produce/consume round-trip, ctx-cancel exit, MaxMessages early-return. Tens of seconds; requires Docker.
- **E2E (compose)** (`make e2e-compose`): `e2e/docker-compose.e2e.yml` boots PLAINTEXT Kafka + builds **both** Dockerfiles (`Dockerfile.consumer` long-lived service, `Dockerfile.producer` one-shot job). Asserts the producer-binary publish path AND the consumer-binary consume path round-trip via a real broker.
- **E2E (KinD)** (`make e2e`): `e2e/e2e-kind-test.sh` deploys real `k8s/` manifests (with PLAINTEXT overlays in `e2e/k8s/`) into a throwaway KinD cluster. Pins kubectl to `kind-kafka-e2e` context (`KUBECTL=(kubectl --context=kind-kafka-e2e)`) so a sibling project's `kubectl config use-context` cannot redirect calls to the wrong cluster. The Kafka rollout step retries up to 3× to absorb docker.io pull-rate-limit hiccups.

### Running

```bash
make kafka-run-producer    # Build and run producer
make kafka-run-consumer    # Build and run consumer
make consumer-image-run    # Run consumer via Docker Compose
```

### Release

```bash
make release               # Tag and push a new semver release
make test-release          # Test GoReleaser build locally via Docker
```

### Kubernetes

```bash
make k8s-deploy            # Deploy to Kubernetes
make k8s-undeploy          # Remove from Kubernetes
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| `setup` | push, PR | Extract Go version from `go.mod` for downstream jobs |
| `static-check` | push, PR | `make static-check` composite |
| `test` | push, PR | Unit tests (matrix: ubuntu-latest + macos-latest) |
| `integration-test` | push, PR | `make integration-test` (Testcontainers-backed; ubuntu-latest) |
| `e2e-compose` | push, PR | `make e2e-compose` (Docker Compose + PLAINTEXT broker; ubuntu-latest) |
| `e2e` | push, PR | `make e2e` (KinD cluster + in-cluster Kafka + real `k8s/` manifests; ubuntu-latest) |
| `build` | push, PR | Matrix: ubuntu-latest + macos-latest |
| `ci-pass` | always | Branch-protection aggregator |
| `release-binaries` | tags only | GoReleaser cross-compilation (Linux + macOS) |
| `docker` | tags only | Multi-arch build (`linux/amd64,linux/arm64`) + Trivy scan + smoke test + push to ghcr.io + cosign sign |

Cleanup workflow (`cleanup-runs.yml`) runs weekly to remove old workflow runs (retains 7 days, keeps minimum 5 runs).

## Code Conventions

- Go modules with `GOFLAGS=-mod=mod`
- `GOPRIVATE` set to this repository
- Binary output directory: `.bin/`
- Use `make ci` to validate changes locally before pushing
- mise (`.mise.toml`) is the single source of truth for the host toolchain — Go, Node, and all lint/security scanners. `make deps` bootstraps mise and runs `mise install`. CI uses `actions/setup-go` (with `go-version-file: go.mod`) for the Go cache and runs `make deps` for everything else
- Docker-image-only tool pins (no host install) live in the Makefile with `# renovate:` inline comments: `MERMAID_CLI_VERSION` (mermaid-cli) and `GOLANG_CROSS_VERSION` (goreleaser-cross). `KIND_VERSION` and `KUBECTL_VERSION` live in `scripts/kind-tools-install.sh` (called by `make kind-tools-install` from both local dev and the CI `e2e` job) — tracked by a third `customManagers` regex in `renovate.json`
- `KUBECTL ?= kubectl` indirection in the Makefile lets `make k8s-deploy KUBECTL='kubectl --context=...'` pin a specific cluster without changing the recipe; the e2e KinD harness pins `kubectl --context=kind-${CLUSTER}` inline (see `e2e/e2e-kind-test.sh`) to defend against sibling projects swapping the global current-context

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
