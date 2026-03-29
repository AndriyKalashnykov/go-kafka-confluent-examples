[![CI](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml/badge.svg)](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/go-kafka-confluent-examples.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/go-kafka-confluent-examples/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/go-kafka-confluent-examples)

# Confluent Kafka Cloud Go Example

Go-based [Confluent Kafka Cloud](https://confluent.cloud/) producer/consumer examples using the [confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go/) client, with Kubernetes deployment support and Docker containerization.

## Quick Start

```bash
make deps                  # verify required tools are installed
make build                 # build producer and consumer binaries
make test                  # run tests
make kafka-run-producer    # build and run producer
make kafka-run-consumer    # build and run consumer
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Go](https://go.dev/dl/) | 1.26+ | Language runtime and compiler |
| [gvm](https://github.com/moovweb/gvm) | latest | Go version management (optional) |
| [Docker](https://www.docker.com/) | latest | Container builds and Compose |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | latest | Kubernetes deployment (optional) |
| [Git](https://git-scm.com/) | latest | Version control |

Install all required dependencies:

```bash
make deps
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build producer and consumer binaries |
| `make test` | Run tests |
| `make lint` | Run linters (golangci-lint + hadolint) |
| `make clean` | Cleanup build artifacts |
| `make kafka-run-producer` | Run producer |
| `make kafka-run-consumer` | Run consumer |

### Dependencies

| Target | Description |
|--------|-------------|
| `make deps` | Install and verify required dependencies |
| `make deps-check` | Show required Go versions and gvm status |
| `make get` | Download and install dependency packages |
| `make update` | Update dependency packages to latest versions |

### Docker

| Target | Description |
|--------|-------------|
| `make consumer-image-build` | Build Consumer Docker image |
| `make consumer-image-run` | Run Consumer Docker image via Compose |
| `make consumer-image-stop` | Stop Consumer Docker image |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make k8s-deploy` | Deploy to Kubernetes |
| `make k8s-undeploy` | Undeploy from Kubernetes |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Run all CI checks (lint, test, build) |
| `make ci-run` | Run GitHub Actions workflow locally using [act](https://github.com/nektos/act) |

### Release & Utilities

| Target | Description |
|--------|-------------|
| `make release` | Create and push a new tag |
| `make version` | Print current version (tag) |
| `make test-release` | Test release build locally |
| `make renovate-validate` | Validate Renovate configuration |

## Configure Confluent Kafka Go Client

Following steps are required.

- Create Environment and Cluster - https://confluent.cloud/home
- Export Confluent Environment ID as CONFLUENT_ENV
  ```bash
  xdg-open https://confluent.cloud/environments
  export CONFLUENT_ENV=
  ```
- Export Confluent cluster ID as CONFLUENT_CLUSTER
  ```bash
  xdg-open https://confluent.cloud/environments/$CONFLUENT_ENV/clusters
  export CONFLUENT_CLUSTER=
  ```
- Select Environment
  ```bash
  confluent environment use $CONFLUENT_ENV
  ```
- Select Cluster
  ```bash
  confluent kafka cluster use $CONFLUENT_CLUSTER
  confluent login --save
  ```
- Create a new API key and secret pair
  ```bash
  confluent api-key create --resource $CONFLUENT_CLUSTER
  ```
- Export previously created KEY and SECRET
  ```bash
  export CONFLUENT_API_KEY=
  export CONFLUENT_API_SECRET=
  ```

- Use an API key and secret in the CLI
  ```bash
  confluent api-key use $CONFLUENT_API_KEY --resource $CONFLUENT_CLUSTER
  ```

- Export Confluent Kafka Cluster Bootstrap Server - `Cluster settings -> Endpoints -> Bootstrap server`, create
  kafka.properties from the template and add it to the git repository.
  ```bash
  xdg-open https://confluent.cloud/environments/$CONFLUENT_ENV/clusters/$CONFLUENT_CLUSTER/settings/kafka
  export CONFLUENT_BOOTSTRAP_SERVER=
  sed -e "s%BTSTRP%$CONFLUENT_BOOTSTRAP_SERVER%g" ./tmpl/kafka.properties.tmpl > ./kafka.properties
  ```
- Create .env file
  ```bash
  sed -e "s%BTSTRP%$CONFLUENT_BOOTSTRAP_SERVER%g" -e "s%APIKEY%$CONFLUENT_API_KEY%g" -e "s%APISECRET%$CONFLUENT_API_SECRET%g" ./tmpl/.env.tmpl > ./.env
  ```
- Create Confluent Kafka topic
  ```bash
  confluent kafka topic create test-topic
  ```

## Test Confluent Kafka Topic

```bash
confluent kafka topic list
confluent kafka topic produce test-topic
confluent kafka topic consume -b test-topic
```

## Deploy Confluent Kafka Consumer to Kubernetes

To deploy on Kubernetes create configmap and secret:

```bash
# create configmap from Kafka properties file
kubectl create configmap kafka-config --from-file kafka.properties -o yaml --dry-run=client >./k8s/cm.yaml

# store $CONFLUENT_API_KEY and $CONFLUENT_API_SECRET as k8s secret
sed -e"s%USR%`echo -n $CONFLUENT_API_KEY|base64 -w0`%g" -e "s%PWD%`echo -n $CONFLUENT_API_SECRET|base64 -w0`%g" ./tmpl/sc.yaml.tmpl > ./k8s/sc.yaml
```

and then run

```bash
make k8s-deploy
```

## Run Confluent Kafka Consumer Docker Image Locally

```bash
make consumer-image-run
```

## Run Confluent Kafka Producer Locally

```bash
make kafka-run-producer
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **ci** | push, PR, tags | Lint, Test, Build (matrix: ubuntu + macos) |
| **release-binaries** | tags only | GoReleaser cross-compilation (Linux + macOS) |
| **release-docker-images** | tags only | Docker build and push to ghcr.io |

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.
