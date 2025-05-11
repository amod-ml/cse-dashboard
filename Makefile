# ---------- configurable defaults ----------
AWS_PROFILE ?= private          # set AWS profile, e.g. `make deploy AWS_PROFILE=prod`
AWS_REGION  ?= us-east-1
APP_NAME    ?= dash-lambda      # → Lambda & ECR repo name

# ---------- derived vars ----------
AWS_ACCOUNT := $(shell aws sts get-caller-identity                      \
                           --query Account --output text                \
                           --profile $(AWS_PROFILE))
ECR_URI     := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com/$(APP_NAME)

# ---------- Lambda performance tuning ----------
# Default values can be overridden at call-time, e.g. `make provision PROVISIONED=10`

MEM_SIZE     ?= 2048  # MB
PROVISIONED  ?= 2     # concurrent instances kept warm

# ---------- targets ----------
.PHONY: help ecr docker-login build push deploy config alias-live provision

help:      ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

ecr:       ## Verify or create the ECR repository
	@aws ecr describe-repositories                 \
	      --repository-names $(APP_NAME)           \
	      --region $(AWS_REGION)                   \
	      --profile $(AWS_PROFILE) >/dev/null 2>&1 || \
	aws ecr create-repository                      \
	      --repository-name $(APP_NAME)            \
	      --region $(AWS_REGION)                   \
	      --profile $(AWS_PROFILE)

docker-login:  ## Authenticate Docker to ECR
	@aws ecr get-login-password                    \
	      --region $(AWS_REGION)                   \
	      --profile $(AWS_PROFILE) | \
	docker login --username AWS --password-stdin    \
	      $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com

build: ecr docker-login ## Build multi-arch (arm64) image & push
	docker buildx build                              \
	    --platform linux/arm64                       \
	    --provenance=false --sbom=false              \
	    --tag $(ECR_URI):latest                      \
	    --output type=image,push=true                \
	    .

push: ## No-op (image already pushed by buildx); keep for symmetry
	@echo "Image is at $(ECR_URI):latest"

deploy: build ## Build, push, then point Lambda to new image
	@aws lambda update-function-code                \
	      --function-name $(APP_NAME)               \
	      --image-uri $(ECR_URI):latest             \
	      --publish                                  \
	      --region $(AWS_REGION)                    \
	      --profile $(AWS_PROFILE)
	@echo "✅ Lambda $(APP_NAME) updated to latest image"

lint: ## Lint the code
	ruff check .

format: ## Format the code
	ruff format .

fix: ## Fix the code
	ruff check --fix .

# Update the function configuration (memory, timeout, etc.).
config: ## Update Lambda memory/timeout to improve cold-starts
	aws lambda update-function-configuration \
	  --function-name $(APP_NAME) \
	  --memory-size $(MEM_SIZE) \
	  --timeout 30 \
	  --region $(AWS_REGION) \
	  --profile $(AWS_PROFILE)

# Point/create an alias called "live" at the latest published version.
alias-live: ## Create or update the 'live' alias to the latest version
	$(eval LATEST_VER=$(shell aws lambda list-versions-by-function --function-name $(APP_NAME) --region $(AWS_REGION) --profile $(AWS_PROFILE) --query 'Versions[-1].Version' --output text))
	-aws lambda update-alias \
	  --function-name $(APP_NAME) \
	  --function-version $(LATEST_VER) \
	  --name live \
	  --region $(AWS_REGION) \
	  --profile $(AWS_PROFILE) || true
	-aws lambda create-alias \
	  --function-name $(APP_NAME) \
	  --function-version $(LATEST_VER) \
	  --name live \
	  --region $(AWS_REGION) \
	  --profile $(AWS_PROFILE) || true

# Allocate provisioned concurrency to eliminate cold-starts in production.
provision: alias-live ## Attach provisioned concurrency to alias 'live'
	aws lambda put-provisioned-concurrency-config \
	  --function-name $(APP_NAME) \
	  --qualifier live \
	  --provisioned-concurrent-executions $(PROVISIONED) \
	  --region $(AWS_REGION) \
	  --profile $(AWS_PROFILE)
