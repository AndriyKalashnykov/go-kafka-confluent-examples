.DEFAULT_GOAL := help

CONSUMER_IMG ?= kafka-confluent-go-consumer:latest
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')
GOFLAGS=-mod=mod
GOPRIVATE=github.com/AndriyKalashnykov/go-kafka-confluent-examples
OS ?= $(shell uname -s | tr A-Z a-z)
#OS:= $(shell echo $(OSRAW) | tr A-Z a-z)
#UNAMEOEXISTS=$(shell uname -o &>/dev/null; echo $$?)
#ifeq ($(UNAMEOEXISTS),0)
#  OS=$(shell uname -o)
#else
#  OS=$(shell uname -s)
#endif

# include .env
define setup_env
$(eval include .env)
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' .env))
endef
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' .env))

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#clean: @ Cleanup
clean:
	@rm -rf .bin/

#build: @ Build
build: clean
	@export GOPRIVATE=$(GOPRIVATE); export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=1; go build -o .bin/producer producer/producer.go
	@export GOPRIVATE=$(GOPRIVATE); export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=1; go build -o .bin/consumer consumer/consumer.go

#test: @ Run tests
test:
	@export export GOFLAGS=$(GOFLAGS); go test ./...

#update: @ Update dependency packages to latest versions
update:
	@export GOPRIVATE=$(GOPRIVATE); export GOFLAGS=$(GOFLAGS); cd ./producer; go get -u; go mod tidy; cd ..
	@export GOPRIVATE=$(GOPRIVATE); export GOFLAGS=$(GOFLAGS); cd ./consumer; go get -u; go mod tidy; cd ..

#get: @ Download and install dependency packages
get:
	@export GOPRIVATE=$(GOPRIVATE); export GOFLAGS=$(GOFLAGS); go get ./... ; go mod tidy

#release: @ Create and push a new tag
release:
	$(eval NT=$(NEWTAG))
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add -A
	@git commit -a -s -m "Cut ${NT} release"
	@git tag ${NT}
	@git push origin ${NT}
	@git push
	@echo "Done."

#version: @ Print current version(tag)
version:
	@echo $(shell git describe --tags --abbrev=0)

#consumer-image-build: @ Build Consumer Docker image
consumer-image-build: build
	docker build -t ${CONSUMER_IMG} -f Dockerfile.consumer .

#consumer-image-run: @ Run a Docker image
consumer-image-run: consumer-image-stop
	$(call setup_env)
	docker compose -f "docker-compose.yml" up

#consumer-image-stop: @ Run a Docker image
consumer-image-stop:
	docker compose -f "docker-compose.yml" down

#runp: @ Run producer
runp: build
	$(call setup_env)
#	@echo ${KAFKA_CONFIG_FILE}
	@.bin/producer

#runc: @ Run consumer
runc: build
	$(call setup_env)
#	@echo ${KAFKA_CONFIG_FILE}
	@.bin/consumer

test-release: clean
	goreleaser release -f goreleaser-${OS}.yml --skip-publish --clean --snapshot

#k8s-deploy: @ Deploy to Kubernetes
k8s-deploy:
	@cat ./k8s/ns.yaml | kubectl apply -f - && \
	cat ./k8s/cm.yaml | kubectl apply --namespace=kafka-confluent-examples -f - && \
	cat ./k8s/sc.yaml | kubectl apply --namespace=kafka-confluent-examples -f - && \
	cat ./k8s/deployment.yaml | kubectl apply --namespace=kafka-confluent-examples -f - && \
	cat ./k8s/service.yaml | kubectl apply --namespace=kafka-confluent-examples -f -

#k8s-undeploy: @ Undeploy from Kubernetes
k8s-undeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/service.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/sc.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/cm.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

# ssh into pod
# kubectl exec --stdin --tty -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh -- /bin/sh

# pod logs
# kubectl logs -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh --follow --timestamps

# docker pull --platform=linux/amd64 ghcr.io/andriykalashnykov/kafka-confluent-go-consumer:v0.0.12
# docker inspect 6b7fe811d63f | jq .[].Architecture