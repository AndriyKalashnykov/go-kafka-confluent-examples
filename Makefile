SHELL := /bin/bash
export PATH := $(HOME)/.local/bin:$(PATH)

CONSUMER_IMG ?= kafka-confluent-go-consumer:v0.0.61
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (current tag - ${CURRENTTAG}): " newtag; echo $$newtag')
GOFLAGS=-mod=mod
GOPRIVATE=github.com/AndriyKalashnykov/go-kafka-confluent-examples
OS ?= $(shell uname -s | tr A-Z a-z)
ENVFILE=./.env
OSXCROSS_PATH=/opt/osxcross-clang-17.0.3-macosx-14.0/target/bin

# === Tool Versions (pinned) ===
# renovate: datasource=github-releases depName=golangci/golangci-lint
GOLANGCI_VERSION := 2.11.4
# renovate: datasource=github-releases depName=nektos/act
ACT_VERSION      := 0.2.87
# renovate: datasource=github-releases depName=hadolint/hadolint
HADOLINT_VERSION := 2.14.0
# renovate: datasource=go depName=golang.org/x/vuln/cmd/govulncheck
GOVULNCHECK_VERSION := 1.2.0
# renovate: datasource=github-releases depName=securego/gosec
GOSEC_VERSION    := 2.25.0
# renovate: datasource=github-releases depName=zricethezav/gitleaks
GITLEAKS_VERSION := 8.30.1
# renovate: datasource=github-releases depName=rhysd/actionlint
ACTIONLINT_VERSION := 1.7.12
# renovate: datasource=github-releases depName=aquasecurity/trivy
TRIVY_VERSION    := 0.69.3
# renovate: datasource=github-releases depName=koalaman/shellcheck
SHELLCHECK_VERSION := 0.11.0
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

# Parse Go version from root go.mod (used for release docker builder image tag)
GO_VERSION  := $(shell grep -oP '^go \K[0-9.]+' go.mod)
GO_BUILDER_VERSION := v$(GO_VERSION)

# Node version derived from .nvmrc (mise reads it natively)
NODE_VERSION := $(shell cat .nvmrc 2>/dev/null || echo 24)

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
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-24s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install and verify required toolchain (Go via mise)
deps:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@command -v go >/dev/null 2>&1 || { \
		echo "Installing Go via mise from .mise.toml..."; \
		mise install; \
	}
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v golangci-lint >/dev/null 2>&1 || { echo "Installing golangci-lint $(GOLANGCI_VERSION)..."; \
		go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v$(GOLANGCI_VERSION); }

#deps-check: @ Show required Go version and mise status
deps-check:
	@echo "Go version required: $(GO_VERSION) (from go.mod)"
	@echo "Node version required: $(NODE_VERSION) (from .nvmrc)"
	@command -v mise >/dev/null 2>&1 && mise list || echo "mise not installed - install from https://mise.jdx.dev"

#deps-act: @ Install act for local CI
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		mkdir -p $(HOME)/.local/bin; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b $(HOME)/.local/bin v$(ACT_VERSION); \
	}

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint: deps
	@command -v hadolint >/dev/null 2>&1 || { \
		OS_NAME=$$(uname -s); \
		mkdir -p $(HOME)/.local/bin; \
		if [ "$$OS_NAME" = "Linux" ]; then \
			echo "Installing hadolint $(HADOLINT_VERSION)..."; \
			curl -sSfL -o $(HOME)/.local/bin/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
			chmod +x $(HOME)/.local/bin/hadolint; \
		elif [ "$$OS_NAME" = "Darwin" ]; then \
			echo "Installing hadolint $(HADOLINT_VERSION) (macOS)..."; \
			curl -sSfL -o $(HOME)/.local/bin/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Darwin-x86_64 && \
			chmod +x $(HOME)/.local/bin/hadolint; \
		else \
			echo "Unsupported OS for hadolint install: $$OS_NAME"; exit 1; \
		fi; \
	}

#deps-govulncheck: @ Install govulncheck
deps-govulncheck: deps
	@command -v govulncheck >/dev/null 2>&1 || { echo "Installing govulncheck $(GOVULNCHECK_VERSION)..."; \
		go install golang.org/x/vuln/cmd/govulncheck@v$(GOVULNCHECK_VERSION); }

#deps-gosec: @ Install gosec
deps-gosec: deps
	@command -v gosec >/dev/null 2>&1 || { echo "Installing gosec $(GOSEC_VERSION)..."; \
		go install github.com/securego/gosec/v2/cmd/gosec@v$(GOSEC_VERSION); }

#deps-gitleaks: @ Install gitleaks
deps-gitleaks: deps
	@command -v gitleaks >/dev/null 2>&1 || { echo "Installing gitleaks $(GITLEAKS_VERSION)..."; \
		go install github.com/zricethezav/gitleaks/v8@v$(GITLEAKS_VERSION); }

#deps-actionlint: @ Install actionlint
deps-actionlint: deps
	@command -v actionlint >/dev/null 2>&1 || { echo "Installing actionlint $(ACTIONLINT_VERSION)..."; \
		go install github.com/rhysd/actionlint/cmd/actionlint@v$(ACTIONLINT_VERSION); }

#deps-shellcheck: @ Install shellcheck (required for actionlint shell-script linting)
deps-shellcheck: deps
	@command -v shellcheck >/dev/null 2>&1 || { \
		OS_NAME=$$(uname -s | tr A-Z a-z); \
		ARCH=$$(uname -m); \
		mkdir -p $(HOME)/.local/bin; \
		echo "Installing shellcheck $(SHELLCHECK_VERSION)..."; \
		curl -sSfL -o /tmp/shellcheck.tar.xz "https://github.com/koalaman/shellcheck/releases/download/v$(SHELLCHECK_VERSION)/shellcheck-v$(SHELLCHECK_VERSION).$${OS_NAME}.$${ARCH}.tar.xz" && \
		tar -xJf /tmp/shellcheck.tar.xz -C /tmp && \
		install -m 755 /tmp/shellcheck-v$(SHELLCHECK_VERSION)/shellcheck $(HOME)/.local/bin/shellcheck && \
		rm -rf /tmp/shellcheck-v$(SHELLCHECK_VERSION) /tmp/shellcheck.tar.xz; \
	}

#deps-trivy: @ Install Trivy for security scanning
deps-trivy: deps
	@command -v trivy >/dev/null 2>&1 || { \
		OS_NAME=$$(uname -s); \
		ARCH=$$(uname -m); \
		case "$$ARCH" in x86_64) ARCH_NAME=64bit ;; aarch64|arm64) ARCH_NAME=ARM64 ;; *) ARCH_NAME=$$ARCH ;; esac; \
		echo "Installing trivy $(TRIVY_VERSION) for $$OS_NAME-$$ARCH_NAME..."; \
		mkdir -p $(HOME)/.local/bin; \
		curl -sSfL -o /tmp/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION)_$${OS_NAME}-$${ARCH_NAME}.tar.gz" && \
		tar -xzf /tmp/trivy.tar.gz -C /tmp trivy && \
		install -m 755 /tmp/trivy $(HOME)/.local/bin/trivy && \
		rm -f /tmp/trivy /tmp/trivy.tar.gz; \
	}

#clean: @ Cleanup
clean:
	@rm -rf .bin/ dist/

#format: @ Format Go code
format: deps
	@gofmt -s -w .
	@command -v goimports >/dev/null 2>&1 && goimports -w . || true

#format-check: @ Verify code is formatted
format-check: deps
	@test -z "$$(gofmt -s -l .)" || { echo "Code not formatted. Run 'make format'"; gofmt -s -l .; exit 1; }

#deps-prune: @ Remove unused Go dependencies
deps-prune: deps
	@go mod tidy

#deps-prune-check: @ Verify go.mod and go.sum are clean
deps-prune-check: deps
	@cp go.mod go.mod.bak && cp go.sum go.sum.bak
	@go mod tidy
	@diff -q go.mod go.mod.bak >/dev/null && diff -q go.sum go.sum.bak >/dev/null || { \
		echo "go.mod/go.sum not tidy. Run 'make deps-prune'"; \
		mv go.mod.bak go.mod; mv go.sum.bak go.sum; exit 1; }
	@rm -f go.mod.bak go.sum.bak

#lint: @ Run golangci-lint + hadolint
lint: deps deps-hadolint
	@export CGO_ENABLED=1 && golangci-lint run ./...
	@command -v hadolint >/dev/null 2>&1 && hadolint Dockerfile.consumer || true

#vulncheck: @ Run govulncheck
vulncheck: deps-govulncheck
	@govulncheck ./...

#sec: @ Run gosec static security analysis
sec: deps-gosec
	@gosec -quiet ./... || { echo "gosec found issues"; exit 1; }

#secrets: @ Run gitleaks secret scan
secrets: deps-gitleaks
	@gitleaks detect --no-banner --source .

#lint-ci: @ Run actionlint on GitHub workflows
lint-ci: deps-actionlint deps-shellcheck
	@actionlint

#trivy-fs: @ Trivy filesystem scan (secrets + misconfigs; Go CVEs handled by govulncheck)
trivy-fs: deps-trivy
	@trivy fs --scanners secret,misconfig --severity CRITICAL,HIGH --exit-code 1 .

#mermaid-lint: @ Parse-check every ```mermaid block in markdown files via pinned mermaid-cli (same engine github.com uses)
mermaid-lint:
	@set -euo pipefail; \
	files=$$(git ls-files '*.md' | xargs -r grep -l '^```mermaid' 2>/dev/null || true); \
	if [ -z "$$files" ]; then echo "No Mermaid blocks found, skipping"; exit 0; fi; \
	rm -rf .bin/mermaid-lint && mkdir -p .bin/mermaid-lint; \
	for f in $$files; do \
	  out=".bin/mermaid-lint/$$(echo $$f | tr / _).out.md"; \
	  docker run --rm -u $$(id -u):$$(id -g) \
	    -v "$(CURDIR):/work" -w /work \
	    minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
	    -i "$$f" -o "$$out" >/dev/null; \
	done; \
	echo "Mermaid parse OK: $$files"

#static-check: @ Composite quality gate (format-check + deps-prune-check + lint + lint-ci + sec + vulncheck + secrets + trivy-fs + mermaid-lint)
static-check: format-check deps-prune-check lint lint-ci sec vulncheck secrets trivy-fs mermaid-lint

#test: @ Run unit tests
test: deps
	@export GOFLAGS=$(GOFLAGS) && go test -race -cover ./...

#integration-test: @ Run integration tests (Testcontainers-backed; opt-in via -tags=integration)
integration-test: deps
	@export GOFLAGS=$(GOFLAGS) && go test -race -tags=integration -v ./...

#build: @ Build producer and consumer binaries
build: deps
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) CGO_ENABLED=1 && go build -o .bin/producer producer/producer.go
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) CGO_ENABLED=1 && go build -o .bin/consumer consumer/consumer.go

#ci: @ Run all CI checks (static-check, test, integration-test, build)
ci: deps static-check test integration-test build
	@echo "Local CI pipeline passed."

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#update: @ Update dependency packages to latest versions
update: deps
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./producer && go get -u ./... && go mod tidy && cd ..
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./consumer && go get -u ./... && go mod tidy && cd ..

#get: @ Download and install dependency packages
get: deps
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && go get ./... && go mod tidy

#release: @ Create and push a new tag
release:
	$(eval NT=$(NEWTAG))
	@if ! echo "$(NT)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: tag '$(NT)' is not valid semver (expected vMAJOR.MINOR.PATCH)"; \
		exit 1; \
	fi
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add version.txt
	@git commit -s -m "Cut ${NT} release"
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
	@.bin/producer

#kafka-run-consumer: @ Run consumer
kafka-run-consumer: build
ifneq (,$(wildcard $(ENVFILE)))
	$(call load_env)
endif
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

#e2e-compose: @ Run E2E via Docker Compose (PLAINTEXT Kafka broker + consumer, no SASL)
e2e-compose:
	@./e2e/e2e-compose-test.sh

#e2e: @ Run E2E via KinD cluster (in-cluster Kafka + real k8s/ manifests with PLAINTEXT overrides)
e2e:
	@./e2e/e2e-kind-test.sh

#k8s-deploy: @ Deploy to Kubernetes
k8s-deploy:
	@test -f ./k8s/cm.yaml || { echo "Error: k8s/cm.yaml missing. Generate with: kubectl create configmap kafka-config --from-file kafka.properties -o yaml --dry-run=client > ./k8s/cm.yaml"; exit 1; }
	@test -f ./k8s/sc.yaml || { echo "Error: k8s/sc.yaml missing. Generate from tmpl/sc.yaml.tmpl (see README)"; exit 1; }
	@kubectl apply -f ./k8s/ns.yaml
	@kubectl apply --namespace=kafka-confluent-examples -f ./k8s/cm.yaml
	@kubectl apply --namespace=kafka-confluent-examples -f ./k8s/sc.yaml
	@kubectl apply --namespace=kafka-confluent-examples -f ./k8s/deployment.yaml
	@kubectl apply --namespace=kafka-confluent-examples -f ./k8s/service.yaml

#k8s-undeploy: @ Undeploy from Kubernetes
k8s-undeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/service.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/sc.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/cm.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@command -v node >/dev/null 2>&1 || { echo "Installing Node $(NODE_VERSION) via mise..."; mise install node@$(NODE_VERSION); }
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-check deps-act deps-hadolint deps-govulncheck deps-gosec deps-gitleaks deps-actionlint deps-shellcheck deps-trivy \
	clean format format-check deps-prune deps-prune-check \
	lint vulncheck sec secrets lint-ci trivy-fs mermaid-lint static-check test integration-test e2e-compose e2e build ci ci-run \
	update get release version \
	consumer-image-build consumer-image-run consumer-image-stop \
	kafka-run-producer kafka-run-consumer test-release \
	k8s-deploy k8s-undeploy \
	renovate-validate
