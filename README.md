[![CI](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml/badge.svg)](https://github.com/AndriyKalashnykov/go-kafka-confluent-examples/actions/workflows/ci.yml)
[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FAndriyKalashnykov%2Fgo-kafka-confluent-examples&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/go-kafka-confluent-examples)
# Confluent Kafka Cloud Go example

This example shows how to create a [Confluent Kafka Cloud](https://confluent.cloud/) Producer/Consumer in Go
and deploy it to Kubernetes.

### Requirements

- Linux (Ubuntu) or Mac OS
- [gvm](https://github.com/moovweb/gvm) Go 1.21.1
  ```bash
  gvm install go1.21.1 --prefer-binary --with-build-tools --with-protobuf
  gvm use go1.21.1 --default
  ```
- [Cross compilation on Ubuntu with CGO ] Optional

  Install libraries for cross compilation (Windows, etc.)
  ```
  ./scripts/install-cross-libs-ubuntu.sh
  ```
  Install [osxcross](https://github.com/tpoechtrager/osxcross) for MacOS cross compilation
    ```bash
  ./scripts/install-clang-17-ubuntu.sh
  ./scripts/install-osxcross-ubuntu.sh
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
