[![CI](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml/badge.svg)](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/go-kafka-confluent-examples.svg)](https://hits.sh/github.com/AndriyKalashnykov/go-kafka-confluent-examples/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/go-kafka-confluent-examples)
# Confluent Kafka Cloud Go example

This example shows how to create a [Confluent Kafka Cloud](https://confluent.cloud/) Producer/Consumer in Go
using [Confluent's Golang Client for Apache Kafka](https://github.com/confluentinc/confluent-kafka-go/) client and deploy it to Kubernetes.

### Requirements

- Linux (Ubuntu) or Mac OS
- [gvm](https://github.com/moovweb/gvm) Go 1.24.2
  ```bash
  gvm install go1.24.2 --prefer-binary --with-build-tools --with-protobuf
  gvm use go1.24.2 --default
  ```
- [Cross compilation on Ubuntu with CGO ] Optional

  Install [LLVM Compiler Infrastructure, release 17](https://llvm.org/)
  ```
  ./scripts/install-clang-17-ubuntu.sh
  ```
  Install libraries for cross compilation (Windows, etc.)
  ```
  ./scripts/install-cross-libs-ubuntu.sh
  ```
  Install [osxcross](https://github.com/tpoechtrager/osxcross) for MacOS cross compilation
    ```bash
  ./scripts/install-osxcross-ubuntu.sh
  ```
- [Build ARM Images on x86 Hosts] Optional
  ```bash
  sudo apt-get update && sudo apt-get install -y --no-install-recommends qemu-user-static binfmt-support
  update-binfmts --enable qemu-arm
  update-binfmts --display qemu-arm
  docker buildx build --platform linux/arm64 --file Dockerfile.consumer -t kafka-confluent-go-consumer:latest .
  ```
  
- [Confluent Kafka CLI and tools](https://confluent.cloud/environments/env-pr7kdm/clusters/lkc-v1007n/integrations/cli)
  ```bash
  curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest
  confluent update
  # log in to a Confluent Cloud organization
  confluent login --save
  ```
- [docker](https://docs.docker.com/engine/install/) Optional
- [GoReleaser](https://goreleaser.com/install/) Optional
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) Optional

## Configure Confluent Kafka Go client

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

## Test Confluent Kafka topic

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

## Run Confluent Kafka Consumer Docker image locally

```bash
make consumer-image-run
```

## Run Confluent Kafka Producer locally

```bash
make runp
```

## Help

```text
Commands :
help                 - List available tasks
clean                - Cleanup
build                - Build
test                 - Run tests
update               - Update dependency packages to latest versions
get                  - Download and install dependency packages
release              - Create and push a new tag
version              - Print current version(tag)
consumer-image-build - Build Consumer Docker image
consumer-image-run   - Run a Docker image
consumer-image-stop  - Run a Docker image
runp                 - Run producer
runc                 - Run consumer
k8s-deploy           - Deploy to Kubernetes
k8s-undeploy         - Undeploy from Kubernetes
```
