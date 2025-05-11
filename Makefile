# ---------- configurable defaults ----------
AWS_PROFILE ?= private          # set AWS profile, e.g. `make deploy AWS_PROFILE=prod`
AWS_REGION  ?= us-east-1
APP_NAME    ?= dash-lambda      # → Lambda & ECR repo name

# ---------- derived vars ----------
AWS_ACCOUNT := $(shell aws sts get-caller-identity                      \
                           --query Account --output text                \
                           --profile $(AWS_PROFILE))
ECR_URI     := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com/$(APP_NAME)

# ---------- targets ----------
.PHONY: help ecr docker-login build push deploy

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
	    --output type=image,push=true .

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