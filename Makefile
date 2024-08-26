
.ONESHELL:
ROOT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
EXECUTOR ?= executors/podman-in-podman
IMAGE_NAME ?= $(shell echo "$(EXECUTOR)" | tr '/' '-')

sinclude $(ROOT_DIR)/.local.mk # You could define GITHUB_TOKEN in there, for example

define check_defined
	test -z "$($(1))" && echo -e "\n\033[1;31mVariable $1 must be defined.\033[0m\n" && exit 1
endef

$(IMAGE_NAME):
	@echo "Building $(IMAGE_NAME) from $(EXECUTOR)..."
	podman build -f $(EXECUTOR)/Containerfile -t $(IMAGE_NAME)

bin/CustomRunnerExecutor:
	podman run -it --rm -v $$(pwd):/in -w /in mcr.microsoft.com/dotnet/sdk:8.0 \
		dotnet publish -r linux-x64 -p:PublishSingleFile=true -o bin src/*.fsproj

run: bin/CustomRunnerExecutor $(IMAGE_NAME)
	@$(call check_defined,GITHUB_TOKEN)
	@$(call check_defined,REPO)
	@$(call check_defined,EXECUTOR)
	@export GITHUB_TOKEN=$(GITHUB_TOKEN)
	bin/CustomRunnerExecutor $(REPO) $(EXECUTOR)
	
