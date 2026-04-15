CONSUMER_IMG ?= kafka-confluent-go-consumer:v0.0.61
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (current tag - ${CURRENTTAG}): " newtag; echo $$newtag')
GOFLAGS=-mod=mod
GOPRIVATE=github.com/AndriyKalashnykov/go-kafka-confluent-examples
OS ?= $(shell uname -s | tr A-Z a-z)
ENVFILE=./.env
GO_BUILDER_VERSION=v$(GO_VERSION)
OSXCROSS_PATH=/opt/osxcross-clang-17.0.3-macosx-14.0/target/bin

# === Tool Versions (pinned) ===
# renovate: datasource=github-releases depName=golangci/golangci-lint
GOLANGCI_VERSION := 2.11.4
# renovate: datasource=github-releases depName=nektos/act
ACT_VERSION      := 0.2.87
# renovate: datasource=github-releases depName=hadolint/hadolint
HADOLINT_VERSION := 2.14.0
# renovate: datasource=github-releases depName=nvm-sh/nvm
NVM_VERSION      := 0.40.4

# Parse Go version from root go.mod
GO_VERSION  := $(shell grep -oP '^go \K[0-9.]+' go.mod)

# Helper: detect gvm availability
HAS_GVM := $(shell command -v gvm >/dev/null 2>&1 && echo true || echo false)
define go-exec
$(if $(filter true,$(HAS_GVM)),bash -c '. $$GVM_ROOT/scripts/gvm && gvm use go$(GO_VERSION) >/dev/null && $(1)',bash -c '$(1)')
endef

define load_env
$(eval include $(ENVFILE))
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' $(ENVFILE)))
endef

ifneq (,$(wildcard $(ENVFILE)))
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' $(ENVFILE)))
endif

.DEFAULT_GOAL := help

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install and verify required dependencies
deps:
	@if [ "$(HAS_GVM)" = "true" ]; then \
		bash -c '. $$GVM_ROOT/scripts/gvm && gvm list' 2>/dev/null | grep -q "go$(GO_VERSION)" || { \
			echo "Installing Go $(GO_VERSION) via gvm..."; \
			bash -c '. $$GVM_ROOT/scripts/gvm && gvm install go$(GO_VERSION) -B'; \
		}; \
	else \
		command -v go >/dev/null 2>&1 || { echo "Error: Go required. Install gvm from https://github.com/moovweb/gvm or Go from https://go.dev/dl/"; exit 1; }; \
	fi
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@$(call go-exec,command -v golangci-lint) >/dev/null 2>&1 || { echo "Installing golangci-lint..."; \
		$(call go-exec,go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v$(GOLANGCI_VERSION)); }

#deps-check: @ Show required Go versions and gvm status
deps-check:
	@echo "Go version required: $(GO_VERSION)"
	@command -v gvm >/dev/null 2>&1 && { \
		bash -c '. $$GVM_ROOT/scripts/gvm && gvm list'; \
	} || echo "gvm not installed - install from https://github.com/moovweb/gvm"

#deps-act: @ Install act for local CI
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint:
	@command -v hadolint >/dev/null 2>&1 || { \
		OS_NAME=$$(uname -s); \
		if [ "$$OS_NAME" = "Linux" ]; then \
			echo "Installing hadolint $(HADOLINT_VERSION)..."; \
			curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
			install -m 755 /tmp/hadolint /usr/local/bin/hadolint && \
			rm -f /tmp/hadolint; \
		else \
			echo "Skipping hadolint install on $$OS_NAME (Linux only)"; \
		fi; \
	}

#clean: @ Cleanup
clean:
	@rm -rf .bin/ dist/

#build: @ Build producer and consumer binaries
build: deps
	@$(call go-exec,export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) CGO_ENABLED=1 && go build -o .bin/producer producer/producer.go)
	@$(call go-exec,export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) CGO_ENABLED=1 && go build -o .bin/consumer consumer/consumer.go)

#test: @ Run tests
test: deps
	@$(call go-exec,export GOFLAGS=$(GOFLAGS) && go test ./...)

#lint: @ Run linters (golangci-lint + hadolint)
lint: deps deps-hadolint
	@$(call go-exec,golangci-lint run ./...)
	@if command -v hadolint >/dev/null 2>&1; then hadolint Dockerfile Dockerfile.consumer; fi

#ci: @ Run all CI checks (lint, test, build)
ci: deps lint test build
	@echo "Local CI pipeline passed."

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#update: @ Update dependency packages to latest versions
update: deps
	@$(call go-exec,export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./producer && go get -u ./... && go mod tidy && cd ..)
	@$(call go-exec,export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./consumer && go get -u ./... && go mod tidy && cd ..)

#get: @ Download and install dependency packages
get: deps
	@$(call go-exec,export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && go get ./... && go mod tidy)

#release: @ Create and push a new tag
release:
	$(eval NT=$(NEWTAG))
	@if ! echo "$(NT)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: tag '$(NT)' is not valid semver (expected vMAJOR.MINOR.PATCH)"; \
		exit 1; \
	fi
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
	@docker buildx build --load -t ${CONSUMER_IMG} -f Dockerfile.consumer .

#consumer-image-run: @ Run Consumer Docker image via Compose
consumer-image-run: consumer-image-stop
ifneq (,$(wildcard $(ENVFILE)))
	$(call load_env)
endif
	@docker compose -f "docker-compose.yml" up --build

#consumer-image-stop: @ Stop Consumer Docker image
consumer-image-stop:
	@docker compose -f "docker-compose.yml" down

#kafka-run-producer: @ Run producer
kafka-run-producer: build
ifneq (,$(wildcard $(ENVFILE)))
	$(call load_env)
endif
#	@echo ${KAFKA_CONFIG_FILE}
	@.bin/producer

#kafka-run-consumer: @ Run consumer
kafka-run-consumer: build
ifneq (,$(wildcard $(ENVFILE)))
	$(call load_env)
endif
#	@echo ${KAFKA_CONFIG_FILE}
	@.bin/consumer

#test-release: @ Test release build locally
test-release: clean
	@docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Linux.yml

	@docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Darwin-cross.yml

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

#renovate-bootstrap: @ Install nvm and npm for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install --lts; \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@npx --yes renovate --platform=local

.PHONY: help deps deps-check deps-act deps-hadolint clean build test lint ci ci-run \
	update get release version \
	consumer-image-build consumer-image-run consumer-image-stop \
	kafka-run-producer kafka-run-consumer test-release \
	k8s-deploy k8s-undeploy \
	renovate-bootstrap renovate-validate
