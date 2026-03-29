# CLAUDE.md

## Project Overview

Go-based Confluent Kafka Cloud producer/consumer examples using the [confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go/) client, with Kubernetes deployment support and Docker containerization.

## Tech Stack

- **Language**: Go 1.26
- **Kafka Client**: confluent-kafka-go v2
- **Build**: Make, GoReleaser (cross-compilation)
- **Container**: Docker, Docker Compose
- **Orchestration**: Kubernetes
- **CI/CD**: GitHub Actions
- **Linting**: golangci-lint, hadolint
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
make help          # List all available targets
make build         # Build producer and consumer binaries (output: .bin/)
make test          # Run tests
make lint          # Run golangci-lint and hadolint
make ci            # Run all CI checks (lint, test, build)
make ci-run        # Run GitHub Actions workflow locally via act
make clean         # Remove build artifacts
make deps          # Install and verify required tools
make deps-check    # Show required Go versions and gvm status
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
| **ci** | push, PR, tags | Lint, Test, Build (matrix: ubuntu + macos) |
| **release-binaries** | tags only | GoReleaser cross-compilation (Linux + macOS) |
| **release-docker-images** | tags only | Docker build and push to ghcr.io |

Cleanup workflow (`cleanup-runs.yml`) runs weekly to remove old workflow runs (retains 7 days, keeps minimum 5 runs).

## Code Conventions

- Go modules with `GOFLAGS=-mod=mod`
- `GOPRIVATE` set to this repository
- Binary output directory: `.bin/`
- Use `make ci` to validate changes locally before pushing
- Use gvm for local Go version management; CI uses `actions/setup-go` with `go-version-file: go.mod`
- Tool versions pinned in Makefile (GOLANGCI_VERSION, ACT_VERSION, HADOLINT_VERSION)

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
