# CLAUDE.md

## Project Overview

Go-based Confluent Kafka Cloud producer/consumer examples using the [confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go/) client, with Kubernetes deployment support and Docker containerization.

## Tech Stack

- **Language**: Go 1.26.2
- **Kafka Client**: confluent-kafka-go v2.14.0 (CGO, `librdkafka`)
- **Build**: Make, GoReleaser (cross-compilation)
- **Container**: Docker, Docker Compose
- **Orchestration**: Kubernetes
- **CI/CD**: GitHub Actions
- **Version manager**: mise (`.mise.toml`, `.nvmrc`)
- **Static analysis**: golangci-lint, gosec, govulncheck, gitleaks, actionlint, shellcheck, hadolint, trivy (filesystem + K8s misconfigs)
- **Dependency Management**: Renovate

## Project Structure

```
producer/          - Kafka producer application
consumer/          - Kafka consumer application
internal/          - Shared internal packages
k8s/               - Kubernetes manifests (ns, cm, sc, deployment, service)
scripts/           - Setup scripts (cross-compilation, toolchain install)
tmpl/              - Template files (.env, kafka.properties, k8s secrets)
.github/workflows/ - CI/CD workflows
```

## Build & Development

```bash
make help           # List all available targets
make build          # Build producer and consumer binaries (output: .bin/)
make test           # Unit tests (fast, no external deps; -race -cover)
make integration-test # Integration tests (Testcontainers-backed, -tags=integration)
make format         # Format Go code
make lint           # Run golangci-lint and hadolint
make static-check   # Composite quality gate (format-check + deps-prune-check + lint + lint-ci + sec + vulncheck + secrets + trivy-fs)
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
| `build` | push, PR | Matrix: ubuntu-latest + macos-latest |
| `ci-pass` | always | Branch-protection aggregator |
| `release-binaries` | tags only | GoReleaser cross-compilation (Linux + macOS) |
| `docker` | tags only | Build + Trivy scan + smoke test + push to ghcr.io + cosign sign |

Cleanup workflow (`cleanup-runs.yml`) runs weekly to remove old workflow runs (retains 7 days, keeps minimum 5 runs).

## Code Conventions

- Go modules with `GOFLAGS=-mod=mod`
- `GOPRIVATE` set to this repository
- Binary output directory: `.bin/`
- Use `make ci` to validate changes locally before pushing
- mise manages the Go + Node toolchain (`.mise.toml`, `.nvmrc`); CI uses `actions/setup-go` with `go-version-file: go.mod`
- Tool versions pinned in Makefile (`GOLANGCI_VERSION`, `ACT_VERSION`, `HADOLINT_VERSION`, `GOVULNCHECK_VERSION`, `GOSEC_VERSION`, `GITLEAKS_VERSION`, `ACTIONLINT_VERSION`, `SHELLCHECK_VERSION`, `TRIVY_VERSION`) with `# renovate:` inline comments

## Upgrade Backlog

- [ ] **Multi-arch Docker image** (`linux/arm64`) — requires CGO cross-compilation for `librdkafka` (cross-gcc, arm64 musl-dev, QEMU emulation). Non-trivial for CGO projects. Currently single-arch (`linux/amd64`). Other hardening gates (Trivy image scan, smoke test, cosign keyless signing) already applied in the `docker` job.
- [ ] **Fix Testcontainers Kafka networking** — `internal/kafkaroundtrip/roundtrip_integration_test.go` is present and compiles, but gated on `RUN_KAFKA_INTEGRATION=1` because `testcontainers-go/modules/kafka@0.42.0` with `confluentinc/confluent-local:7.8.0` fails to rewrite `KAFKA_ADVERTISED_LISTENERS` to the dynamic host port on some hosts — the broker reports `localhost:9092` (unmapped) in metadata and the producer's `Flush` blocks forever waiting for delivery reports. Follow-up: switch to a `GenericContainer` with hand-written env vars that derive `KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:${HOST_PORT}` via the Reaper hook pattern. Once fixed, wire `RUN_KAFKA_INTEGRATION=1` into the CI `integration-test` job.
- [ ] **E2E tests** — Docker Compose flow (`make e2e-compose` with a Kafka broker sidecar + SASL-free test fixture) and KinD flow (`make e2e` with a Kafka StatefulSet) are deferred. Both blocked on: (1) adding a broker to `docker-compose.yml` or a KinD-deployable Kafka manifest, (2) the same Testcontainers networking work above.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
