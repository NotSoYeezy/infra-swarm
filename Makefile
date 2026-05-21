.DEFAULT_GOAL := help

SHELL := powershell.exe
.SHELLFLAGS := -NoProfile -ExecutionPolicy Bypass -Command

PROJECT_NAME := infraswarm
KUBE_CONTEXT ?= minikube
KUBE_NAMESPACE ?= infraswarm
MINIKUBE_CPUS ?= 2
MINIKUBE_MEMORY ?= 3917
AGENTS_DIR := agents

SAMPLE_APP_IMAGE ?= infra-swarm-sample-app
SAMPLE_APP_TAG ?= $(shell powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss")
SAMPLE_APP_FULL_IMAGE := $(SAMPLE_APP_IMAGE):$(SAMPLE_APP_TAG)

.PHONY: help
help: ## Show available targets.
	@Write-Host ""; Write-Host "$(PROJECT_NAME) targets:"; Write-Host ""; Get-Content "$(firstword $(MAKEFILE_LIST))" | Select-String -Pattern '^[a-zA-Z0-9_-]+:.*##' | ForEach-Object { $$parts = $$_.Line -split ':.*##', 2; Write-Host ('  {0,-20} {1}' -f $$parts[0], $$parts[1].Trim()) }

.PHONY: check-tools
check-tools: ## Check local tool dependencies for the foundation stack.
	@foreach ($$tool in @('go', 'uv', 'kubectl', 'minikube')) { if (-not (Get-Command $$tool -ErrorAction SilentlyContinue)) { Write-Error "$$tool is required"; exit 1 } }; Write-Host "Foundation tools found."

.PHONY: setup
setup: check-tools python-sync ## Prepare the local development environment.
	@Write-Host "Local development environment is ready."

.PHONY: python-sync
python-sync: ## Install/sync Python agent dependencies with uv.
	Set-Location "$(AGENTS_DIR)"; uv sync

.PHONY: go-test
go-test: ## Run Go tests.
	go test ./...

.PHONY: python-test
python-test: ## Run Python tests when pytest is available.
	Set-Location "$(AGENTS_DIR)"; uv run pytest

.PHONY: test
test: go-test python-test ## Run all tests.

.PHONY: cluster-up
cluster-up: check-tools ## Start a local Minikube cluster for InfraSwarm.
	minikube start --cpus=$(MINIKUBE_CPUS) --memory=$(MINIKUBE_MEMORY)
	kubectl config use-context $(KUBE_CONTEXT)
	kubectl create namespace $(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: cluster-status
cluster-status: ## Show Minikube and namespace status.
	minikube status
	kubectl get namespace $(KUBE_NAMESPACE)
	kubectl get pods -n $(KUBE_NAMESPACE)

.PHONY: cluster-down
cluster-down: ## Stop the local Minikube cluster.
	minikube stop

.PHONY: cluster-delete
cluster-delete: ## Delete the local Minikube cluster.
	minikube delete

.PHONY: nats-up
nats-up: ## Deploy NATS into the local Kubernetes namespace.
	kubectl create deployment nats --image=nats:2.10-alpine -n $(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl expose deployment nats --port=4222 --target-port=4222 -n $(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: nats-down
nats-down: ## Remove the local NATS deployment and service.
	kubectl delete service nats -n $(KUBE_NAMESPACE) --ignore-not-found
	kubectl delete deployment nats -n $(KUBE_NAMESPACE) --ignore-not-found

.PHONY: nats-port-forward
nats-port-forward: ## Port-forward NATS locally on 4222.
	kubectl port-forward -n $(KUBE_NAMESPACE) service/nats 4222:4222

.PHONY: proto
proto: ## Placeholder for protobuf generation once proto/infraswarm.proto exists.
	@if (-not (Test-Path "proto/infraswarm.proto")) { Write-Host "proto/infraswarm.proto does not exist yet."; exit 0 }; Write-Host "Add protoc generation commands here once contracts are defined."

.PHONY: foundation
foundation: setup cluster-up nats-up ## Bootstrap local dev environment, cluster, and NATS.
	@Write-Host "Foundation stack is up. Next: add proto contracts and sample app manifests."


### Sample app
.PHONY: sample-app-image
sample-app-image: ## Build the sample app Docker image locally
	docker build -f deploy/dockerfiles/sample-app.Dockerfile -t $(SAMPLE_APP_FULL_IMAGE) .

.PHONY: sample-app-load
sample-app-load: sample-app-image ## Load the sample app image into Minikube
	minikube image load $(SAMPLE_APP_FULL_IMAGE)

.PHONY: sample-app-up
sample-app-up: sample-app-load ## Deploy the sample app to Minikube
	kubectl apply -n $(KUBE_NAMESPACE) -f deploy/sample-apps/sample_app_deployment.yaml
	kubectl set image deployment/infra-swarm-sample-app-depl infra-swarm-sample-go-app=$(SAMPLE_APP_FULL_IMAGE) -n $(KUBE_NAMESPACE)
	kubectl rollout status deployment/infra-swarm-sample-app-depl -n $(KUBE_NAMESPACE)

.PHONY: sample-app-forward
sample-app-forward: ## Port forward sample app
	kubectl port-forward -n infraswarm deployment/infra-swarm-sample-app-depl 8080:8080
