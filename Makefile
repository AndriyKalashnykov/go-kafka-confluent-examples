SHELL := /bin/bash
# Make recipes don't source shell rc files, so mise's auto-activation
# isn't in effect inside `$(SHELL) -c '...'`. Put mise's shims dir on
# PATH explicitly so every mise-managed tool (golangci-lint, gosec,
# gitleaks, hadolint, trivy, actionlint, shellcheck, govulncheck, act)
# resolves directly. ~/.local/bin stays on PATH for any tool that's
# still hand-installed.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

CONSUMER_IMG ?= kafka-confluent-go-consumer:v0.0.61
CURRENTTAG := $(shell git describe --tags --abbrev=0)
GOFLAGS = -mod=mod
GOPRIVATE = github.com/AndriyKalashnykov/go-kafka-confluent-examples
OS ?= $(shell uname -s | tr A-Z a-z)
ENVFILE = ./.env
OSXCROSS_PATH = /opt/osxcross-clang-17.0.3-macosx-14.0/target/bin

# === Tool versions managed by mise (.mise.toml) ===
# golangci-lint, act, hadolint, gosec, gitleaks, actionlint, shellcheck,
# trivy, govulncheck — all installed by `mise install`. To bump versions,
# edit .mise.toml; Renovate's mise manager tracks updates automatically.

# === Docker-image-only tool pins (no host install) ===
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0
# renovate: datasource=docker depName=ghcr.io/gythialy/golang-cross
GOLANG_CROSS_VERSION := v1.26.2

# Parse Go version from root go.mod (used for release docker builder image tag)
GO_VERSION := $(shell grep -oP '^go \K[0-9.]+' go.mod)

# Node version derived from .nvmrc (mise reads it natively)
NODE_VERSION := $(shell cat .nvmrc 2>/dev/null || echo 24)

# kubectl indirection — k8s-deploy/k8s-undeploy target the user's selected
# context (production or staging cluster); they are NOT kind-bound. To pin
# a specific cluster, override at invocation:
#   make k8s-deploy KUBECTL='kubectl --context=my-prod-cluster'
# The e2e KinD harness pins its own kubectl context inline (see
# e2e/e2e-kind-test.sh).
KUBECTL ?= kubectl

ifneq (,$(wildcard $(ENVFILE)))
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' $(ENVFILE)))
endif

.DEFAULT_GOAL := help

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z0-9_.\-]+:.*?@ .*$$' $(MAKEFILE_LIST) | tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-24s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install required toolchain via mise (Go, Node, lint/sec scanners)
deps:
	@# In CI, jdx/mise-action installs mise — don't redundantly bootstrap
	@# (skill rule). Locally, install mise on first invocation.
	@if [ -z "$$CI" ]; then \
		command -v mise >/dev/null 2>&1 || { \
			echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
			curl -fsSL https://mise.run | sh; \
		}; \
	fi
	@command -v git >/dev/null 2>&1 || { echo "Error: git is required."; exit 1; }
	@# `mise install` runs in both local and CI so all tool versions resolve.
	@mise install --yes

#deps-check: @ Show required tool versions and mise status
deps-check:
	@echo "Go version required:   $(GO_VERSION) (from go.mod)"
	@echo "Node version required: $(NODE_VERSION) (from .nvmrc)"
	@command -v mise >/dev/null 2>&1 && mise list || echo "mise not installed - install from https://mise.jdx.dev"

#deps-prune: @ Remove unused Go dependencies
deps-prune: deps
	@go mod tidy

#deps-prune-check: @ Verify go.mod and go.sum are clean
deps-prune-check: deps
	@cp go.mod go.mod.bak && cp go.sum go.sum.bak
	@trap 'mv go.mod.bak go.mod 2>/dev/null; mv go.sum.bak go.sum 2>/dev/null' EXIT INT TERM; \
		go mod tidy && \
		diff -q go.mod go.mod.bak >/dev/null && \
		diff -q go.sum go.sum.bak >/dev/null || { \
			echo "go.mod/go.sum not tidy. Run 'make deps-prune'"; exit 1; }
	@rm -f go.mod.bak go.sum.bak

#clean: @ Cleanup
clean:
	@rm -rf .bin/ dist/

#format: @ Format Go code
format: deps
	@gofmt -s -w .

#format-check: @ Verify code is formatted
format-check: deps
	@test -z "$$(gofmt -s -l .)" || { echo "Code not formatted. Run 'make format'"; gofmt -s -l .; exit 1; }

#lint: @ Run golangci-lint and hadolint (both Dockerfiles)
lint: deps
	@export CGO_ENABLED=1 && golangci-lint run ./...
	@hadolint Dockerfile.consumer Dockerfile.producer

#vulncheck: @ Run govulncheck
vulncheck: deps
	@govulncheck ./...

#sec: @ Run gosec static security analysis
sec: deps
	@gosec -quiet ./...

#secrets: @ Run gitleaks secret scan
secrets: deps
	@gitleaks detect --no-banner --source .

#lint-ci: @ Run actionlint on GitHub workflows
lint-ci: deps
	@actionlint

#trivy-fs: @ Trivy filesystem scan (secrets + misconfigs; Go CVEs handled by govulncheck)
trivy-fs: deps
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
ci-run: deps
	@# Pick a random high port for the artifact server so concurrent
	@# `make ci-run` invocations across different repos don't race on
	@# act's default 34567. --artifact-server-path uses a per-run temp
	@# dir for the same reason.
	@#
	@# act's synthetic push-event payload omits `repository.default_branch`,
	@# which dorny/paths-filter requires to compute the diff base. Real
	@# GitHub Actions populates this field automatically; locally we inject
	@# it via --eventpath so the `changes` job behaves the same as in CI.
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	EVENT=$$(mktemp -t act-event.XXXXXX.json); \
	printf '{"repository":{"default_branch":"main"}}\n' > "$$EVENT"; \
	trap 'rm -f "$$EVENT"' EXIT; \
	act push --container-architecture linux/amd64 \
		--eventpath "$$EVENT" \
		--artifact-server-port "$$ACT_PORT" \
		--artifact-server-path "$$(mktemp -d -t act-artifacts.XXXXXX)"

#kind-tools-install: @ Install kind + kubectl into ~/.local/bin (used by CI e2e job and locally)
kind-tools-install:
	@./scripts/kind-tools-install.sh

#update: @ MANUAL escape hatch — Renovate is canonical. Force-bump all Go deps to latest tags.
update: deps
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./producer && go get -u ./... && go mod tidy && cd ..
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && cd ./consumer && go get -u ./... && go mod tidy && cd ..

#get: @ Download and install dependency packages
get: deps
	@export GOPRIVATE=$(GOPRIVATE) GOFLAGS=$(GOFLAGS) && go get ./... && go mod tidy

#release: @ Create and push a new tag (interactive — prompts for semver vMAJOR.MINOR.PATCH)
release:
	@read -r -p "Please provide a new tag (current tag - $(CURRENTTAG)): " NT; \
	if ! echo "$$NT" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: tag '$$NT' is not valid semver (expected vMAJOR.MINOR.PATCH)"; exit 1; \
	fi; \
	read -r -p "Are you sure to create and push $$NT tag? [y/N] " ans; \
	if [ "$${ans:-N}" != "y" ]; then echo "Aborted."; exit 1; fi; \
	echo "$$NT" > ./version.txt && \
	git add version.txt && \
	git commit -s -m "Cut $$NT release" && \
	git tag "$$NT" && \
	git push origin "$$NT" && \
	git push && \
	echo "Done."

#version: @ Print current version(tag)
version:
	@echo $(CURRENTTAG)

#consumer-image-build: @ Build Consumer Docker image
consumer-image-build: build
	@docker buildx build --load -t $(CONSUMER_IMG) -f Dockerfile.consumer .

#consumer-image-run: @ Run Consumer Docker image via Compose
consumer-image-run: consumer-image-stop
	@docker compose -f "docker-compose.yml" up --build

#consumer-image-stop: @ Stop Consumer Docker image
consumer-image-stop:
	@docker compose -f "docker-compose.yml" down

#kafka-run-producer: @ Run producer
kafka-run-producer: build
	@.bin/producer

#kafka-run-consumer: @ Run consumer
kafka-run-consumer: build
	@.bin/consumer

#test-release: @ Test release build locally
test-release: clean
	@docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GOLANG_CROSS_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Linux.yml
	@docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GOLANG_CROSS_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Darwin-cross.yml

#e2e-compose: @ Run E2E via Docker Compose (PLAINTEXT Kafka broker + consumer, no SASL)
e2e-compose:
	@./e2e/e2e-compose-test.sh

#e2e: @ Run E2E via KinD cluster (in-cluster Kafka + real k8s/ manifests with PLAINTEXT overrides)
e2e:
	@./e2e/e2e-kind-test.sh

#k8s-deploy: @ Deploy to Kubernetes (uses $(KUBECTL); override KUBECTL='kubectl --context=...' to pin)
k8s-deploy:
	@test -f ./k8s/cm.yaml || { echo "Error: k8s/cm.yaml missing. Generate with: kubectl create configmap kafka-config --from-file kafka.properties -o yaml --dry-run=client > ./k8s/cm.yaml"; exit 1; }
	@test -f ./k8s/sc.yaml || { echo "Error: k8s/sc.yaml missing. Generate from tmpl/sc.yaml.tmpl (see README)"; exit 1; }
	@$(KUBECTL) apply -f ./k8s/ns.yaml
	@$(KUBECTL) apply --namespace=kafka-confluent-examples -f ./k8s/cm.yaml
	@$(KUBECTL) apply --namespace=kafka-confluent-examples -f ./k8s/sc.yaml
	@$(KUBECTL) apply --namespace=kafka-confluent-examples -f ./k8s/deployment.yaml
	@$(KUBECTL) apply --namespace=kafka-confluent-examples -f ./k8s/service.yaml

#k8s-undeploy: @ Undeploy from Kubernetes (uses $(KUBECTL); override KUBECTL='kubectl --context=...' to pin)
k8s-undeploy:
	@$(KUBECTL) delete -f ./k8s/deployment.yaml --namespace=kafka-confluent-examples --ignore-not-found=true
	@$(KUBECTL) delete -f ./k8s/service.yaml --namespace=kafka-confluent-examples --ignore-not-found=true
	@$(KUBECTL) delete -f ./k8s/sc.yaml --namespace=kafka-confluent-examples --ignore-not-found=true
	@$(KUBECTL) delete -f ./k8s/cm.yaml --namespace=kafka-confluent-examples --ignore-not-found=true
	@$(KUBECTL) delete -f ./k8s/ns.yaml --ignore-not-found=true

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-check deps-prune deps-prune-check \
	clean format format-check \
	lint vulncheck sec secrets lint-ci trivy-fs mermaid-lint static-check \
	test integration-test e2e-compose e2e build ci ci-run kind-tools-install \
	update get release version \
	consumer-image-build consumer-image-run consumer-image-stop \
	kafka-run-producer kafka-run-consumer test-release \
	k8s-deploy k8s-undeploy \
	renovate-validate
