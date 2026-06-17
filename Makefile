# =============================================================================
#  Azure Demo — Terraform Makefile
#  Usage:  make <command> <env> [target='resource'] [auto=true]
#  Envs:   dev | staging | prod
#
#  Reclaimed from aws-stack-tf-default-template — the wrapper mechanics are
#  cloud-agnostic (chdir / backend-config / var-file); only the state backend
#  and auth steps are Azure-specific.
# =============================================================================

# ── colours ──────────────────────────────────────────────────────────────────
BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
YELLOW:= \033[33m
RED   := \033[31m
RESET := \033[0m

# ── config ────────────────────────────────────────────────────────────────────
ENV   := $(word 2,$(MAKECMDGOALS))
TFDIR := terraform

# Shared cloud preflight (CLI detect/install + auth) lives in a sibling repo.
# Override if yours sits elsewhere:  make plan dev BOOTSTRAPER=/path/to/cloud-bootstraper
BOOTSTRAPER ?= ../cloud-bootstraper
PREFLIGHT   := $(BOOTSTRAPER)/cloud-preflight.sh

# Optional flags — pass on the command line:
#   target='azurerm_subnet.this'  → scopes plan/apply/destroy to one or more resources
#   auto=true                      → adds -auto-approve (skips interactive prompt)
TARGET_FLAG  := $(foreach t,$(target),-target=$(t))
APPROVE_FLAG := $(if $(auto),-auto-approve,)

# Paths are resolved relative to $(TFDIR) because we use -chdir
BACKEND_VARS := env/$(ENV)/$(ENV).backend.tfvars
TF_VARS      := env/$(ENV)/$(ENV).terraform.tfvars

# ── guard: require ENV ────────────────────────────────────────────────────────
define require-env
	@[ -n "$(ENV)" ] || { \
		printf "$(RED)$(BOLD)error:$(RESET) no environment specified.\n"; \
		printf "  usage: $(CYAN)make $(1) <env>$(RESET)\n"; \
		printf "  envs:  dev | staging | prod\n"; \
		exit 1; \
	}
endef

# ── help (default target) ─────────────────────────────────────────────────────
.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf "\n$(BOLD)$(CYAN)Azure Demo$(RESET) — Terraform wrapper\n\n"
	@printf "$(BOLD)Usage:$(RESET)\n"
	@printf "  make $(CYAN)<command> <env>$(RESET) $(YELLOW)[target='resource'] [auto=true]$(RESET)\n\n"
	@printf "$(BOLD)Commands:$(RESET)\n"
	@printf "  $(CYAN)bootstrap$(RESET) <env>                  Create the Azure state backend (RG + storage account + container)\n"
	@printf "  $(CYAN)auth$(RESET)      <env>                  Ensure Azure CLI is installed and you're logged in\n"
	@printf "  $(CYAN)init$(RESET)      <env>                  Init backend for the given environment\n"
	@printf "  $(CYAN)plan$(RESET)      <env>                  Preview changes\n"
	@printf "  $(CYAN)apply$(RESET)     <env>                  Apply changes (prompts for confirmation)\n"
	@printf "  $(CYAN)destroy$(RESET)   <env>                  Tear down infrastructure\n"
	@printf "  $(CYAN)validate$(RESET)  <env>                  Validate configuration\n"
	@printf "  $(CYAN)fmt$(RESET)                              Format all .tf files in-place\n\n"
	@printf "$(BOLD)Environments:$(RESET)\n"
	@printf "  dev | staging | prod\n\n"
	@printf "$(BOLD)Options:$(RESET)\n"
	@printf "  $(YELLOW)target='azurerm_subnet.this azurerm_network_security_group.this'$(RESET)  Scope to one or more resources\n"
	@printf "  $(YELLOW)auto=true$(RESET)                      Skip interactive approval prompt\n\n"
	@printf "$(BOLD)Examples:$(RESET)\n"
	@printf "  make init    dev\n"
	@printf "  make plan    dev\n"
	@printf "  make plan    dev  target='azurerm_virtual_network.this'\n"
	@printf "  make apply   dev\n"
	@printf "  make apply   dev  auto=true\n"
	@printf "  make destroy dev  auto=true\n\n"
	@printf "$(BOLD)First-time setup:$(RESET)\n"
	@printf "  cp terraform/env/dev/dev.backend.tfvars.example    terraform/env/dev/dev.backend.tfvars\n"
	@printf "  cp terraform/env/dev/dev.terraform.tfvars.example  terraform/env/dev/dev.terraform.tfvars\n"
	@printf "  # edit both files (set subscription_id), then:\n"
	@printf "  az login\n"
	@printf "  make bootstrap dev   # one-time: creates the storage backend\n"
	@printf "  make init dev\n\n"

# ── preflight (auth) ──────────────────────────────────────────────────────────
# Ensures the Azure CLI is installed (offers to install) and that you have a live
# login session. Runs automatically before bootstrap/init/plan/apply/destroy;
# also callable directly as `make auth <env>`. Shared across clouds via cloud-bootstraper.
.PHONY: preflight auth
auth: preflight
preflight:
	$(call require-env,auth)
	@[ -x "$(PREFLIGHT)" ] || { \
		printf "$(RED)$(BOLD)error:$(RESET) cloud preflight not found: $(PREFLIGHT)\n"; \
		printf "  clone it next to this repo:  git clone https://github.com/espresso20/cloud-bootstraper.git $(BOOTSTRAPER)\n"; \
		printf "  or point at it:  make ... BOOTSTRAPER=/path/to/cloud-bootstraper\n"; \
		exit 1; \
	}
	@sub=$$(sed -n -E 's/^[[:space:]]*subscription_id[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' "$(TFDIR)/$(TF_VARS)" | head -1); \
		"$(PREFLIGHT)" azure "$$sub"

# ── bootstrap ─────────────────────────────────────────────────────────────────
# One-time creation of the Azure Storage backend (resource group + storage
# account + blob container) for an environment, before `init`.
# Solves the chicken-and-egg: the storage holding TF state can't be managed by
# that same state. Idempotent — safe to re-run.
.PHONY: bootstrap
bootstrap: preflight
	$(call require-env,bootstrap)
	@printf "\n$(BOLD)$(CYAN)» bootstrap$(RESET) — environment: $(BOLD)$(ENV)$(RESET)\n\n"
	./scripts/bootstrap-state.sh $(ENV)
	@printf "\n$(GREEN)✓ bootstrap complete$(RESET)\n\n"

# ── init ──────────────────────────────────────────────────────────────────────
# Initialises the azurerm backend for the target environment.
# Use -reconfigure so switching envs doesn't require manual state migration.
.PHONY: init
init: preflight
	$(call require-env,init)
	@printf "\n$(BOLD)$(CYAN)» init$(RESET) — environment: $(BOLD)$(ENV)$(RESET)\n\n"
	terraform -chdir=$(TFDIR) init \
		-backend-config=$(BACKEND_VARS) \
		-reconfigure
	@printf "\n$(GREEN)✓ init complete$(RESET)\n\n"

# ── plan ──────────────────────────────────────────────────────────────────────
.PHONY: plan
plan: preflight
	$(call require-env,plan)
	@printf "\n$(BOLD)$(CYAN)» plan$(RESET) — environment: $(BOLD)$(ENV)$(RESET)"
	@[ -z "$(target)" ] || printf "  target: $(YELLOW)$(target)$(RESET)"
	@printf "\n\n"
	terraform -chdir=$(TFDIR) plan \
		-var-file=$(TF_VARS) \
		$(TARGET_FLAG)
	@printf "\n$(GREEN)✓ plan complete$(RESET)\n\n"

# ── apply ─────────────────────────────────────────────────────────────────────
# Omit auto=true to get Terraform's interactive approval prompt (recommended).
.PHONY: apply
apply: preflight
	$(call require-env,apply)
	@printf "\n$(BOLD)$(CYAN)» apply$(RESET) — environment: $(BOLD)$(ENV)$(RESET)"
	@[ -z "$(target)" ] || printf "  target: $(YELLOW)$(target)$(RESET)"
	@[ -z "$(auto)"   ] || printf "  $(RED)auto-approve$(RESET)"
	@printf "\n\n"
	terraform -chdir=$(TFDIR) apply \
		-var-file=$(TF_VARS) \
		$(TARGET_FLAG) \
		$(APPROVE_FLAG)
	@printf "\n$(GREEN)✓ apply complete$(RESET)\n\n"

# ── destroy ───────────────────────────────────────────────────────────────────
# Destroys all resources in the environment. Be careful.
.PHONY: destroy
destroy: preflight
	$(call require-env,destroy)
	@printf "\n$(BOLD)$(RED)» destroy$(RESET) — environment: $(BOLD)$(ENV)$(RESET)"
	@[ -z "$(target)" ] || printf "  target: $(YELLOW)$(target)$(RESET)"
	@[ -z "$(auto)"   ] || printf "  $(RED)auto-approve$(RESET)"
	@printf "\n\n"
	terraform -chdir=$(TFDIR) destroy \
		-var-file=$(TF_VARS) \
		$(TARGET_FLAG) \
		$(APPROVE_FLAG)
	@printf "\n$(GREEN)✓ destroy complete$(RESET)\n\n"

# ── validate ──────────────────────────────────────────────────────────────────
.PHONY: validate
validate:
	$(call require-env,validate)
	@printf "\n$(BOLD)$(CYAN)» validate$(RESET) — environment: $(BOLD)$(ENV)$(RESET)\n\n"
	terraform -chdir=$(TFDIR) validate
	@printf "\n$(GREEN)✓ validate complete$(RESET)\n\n"

# ── fmt ───────────────────────────────────────────────────────────────────────
# Formats all .tf files recursively. Safe to run at any time.
.PHONY: fmt
fmt:
	@printf "\n$(BOLD)$(CYAN)» fmt$(RESET) — formatting terraform/\n\n"
	terraform -chdir=$(TFDIR) fmt -recursive
	@printf "\n$(GREEN)✓ fmt complete$(RESET)\n\n"

# ── env name no-ops ───────────────────────────────────────────────────────────
# Prevents make from treating env names as unknown targets.
.PHONY: dev staging prod
dev staging prod:
	@:
