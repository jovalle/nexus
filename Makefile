# Docker Compose Management Makefile

# Variables
PWD := $(shell pwd)
STACKS_DIR := $(PWD)/stacks
BACKUP_DIR := $(PWD)/backups
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
COMPOSE := docker compose

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Get all stack directories
STACKS := $(shell find $(STACKS_DIR) -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

.PHONY: help status pull start stop restart logs logs-follow cleanup backup restore list-backups health check-env

# Default target
all: help

help: ## Show this help message
	@echo "$(BLUE)Dockge Stack Management$(NC)"
	@echo "$(YELLOW)Usage: make <command> [STACK=stack_name]$(NC)"
	@echo "$(YELLOW)Available stacks: $(STACKS)$(NC)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  $(GREEN)make start$(NC)           # Start all stacks"
	@echo "  $(GREEN)make start STACK=core$(NC) # Start only core stack"
	@echo "  $(GREEN)make logs STACK=server$(NC)# Show server stack logs"

check-env: ## Check if stack directories exist and have compose files
	@echo "$(BLUE)Checking stack directories...$(NC)"
	@if [ -z "$(STACKS)" ]; then \
		echo "$(RED)Error: No stack directories found in $(STACKS_DIR)$(NC)"; \
		exit 1; \
	fi
	@for stack in $(STACKS); do \
		if [ ! -d "$(STACKS_DIR)/$$stack" ]; then \
			echo "$(RED)Error: Stack directory $(STACKS_DIR)/$$stack does not exist$(NC)"; \
			exit 1; \
		fi; \
		if [ ! -f "$(STACKS_DIR)/$$stack/compose.yaml" ] && [ ! -f "$(STACKS_DIR)/$$stack/docker-compose.yml" ]; then \
			echo "$(RED)Error: No compose file found in $(STACKS_DIR)/$$stack$(NC)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ $(STACKS_DIR)/$$stack$(NC)"; \
	done

status: ## Show status of stacks (STACK=name for specific stack)
	@echo "$(BLUE)Stack Status Overview$(NC)"
	@echo "$(YELLOW)===================$(NC)"
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(BLUE)$(STACK) stack:$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) ps --format table || echo "$(RED)Failed to get status for $(STACK)$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@for stack in $(STACKS); do \
		echo "$(BLUE)$$stack stack:$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) ps --format table || echo "$(RED)Failed to get status for $$stack$(NC)"; \
		echo ""; \
	done
endif

pull: check-env ## Pull latest images (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)Pulling $(STACK) stack images...$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) pull; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Pulling latest images for all stacks...$(NC)"
	@for stack in $(STACKS); do \
		echo "$(YELLOW)Pulling $$stack stack images...$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) pull || echo "$(RED)Failed to pull $$stack$(NC)"; \
	done
endif

start: check-env ## Start stacks (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)Starting $(STACK) stack...$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) up -d; \
		echo "$(GREEN)$(STACK) stack started$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Starting all stacks...$(NC)"
	@for stack in $(STACKS); do \
		echo "$(YELLOW)Starting $$stack stack...$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) up -d --remove-orphans && echo "$(GREEN)$$stack stack started$(NC)" || echo "$(RED)Failed to start $$stack$(NC)"; \
		sleep 2; \
	done
endif

stop: ## Stop stacks (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)Stopping $(STACK) stack...$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) down; \
		echo "$(GREEN)$(STACK) stack stopped$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Stopping all stacks...$(NC)"
	@for stack in $$(echo "$(STACKS)" | tr ' ' '\n' | tac | tr '\n' ' '); do \
		echo "$(YELLOW)Stopping $$stack stack...$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) down && echo "$(GREEN)$$stack stack stopped$(NC)" || echo "$(RED)Failed to stop $$stack$(NC)"; \
	done
endif

restart: ## Restart stacks (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)Restarting $(STACK) stack...$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) down && $(COMPOSE) up -d; \
		echo "$(GREEN)$(STACK) stack restarted$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Restarting all stacks...$(NC)"
	@$(MAKE) stop start
endif

logs: ## Show logs (STACK=name for specific stack, FOLLOW=1 to follow)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)$(STACK) stack logs:$(NC)"; \
		if [ "$(FOLLOW)" = "1" ]; then \
			cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) logs -f; \
		else \
			cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) logs --tail=50; \
		fi; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Recent logs from all stacks:$(NC)"
	@for stack in $(STACKS); do \
		echo "$(YELLOW)$$stack stack logs:$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) logs --tail=20; \
		echo ""; \
	done
endif

tail: ## Follow logs from all stacks (or STACK=name for specific)
ifdef STACK
	@$(MAKE) logs STACK=$(STACK) FOLLOW=1
else
	@echo "$(BLUE)Following logs from all stacks...$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@for stack in $(STACKS); do \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) logs -f & \
	done; \
	wait
endif

health: ## Check health status (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(BLUE)$(STACK) stack health:$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) ps --format table --filter "status=running" | grep -E "(healthy|unhealthy)" || echo "No health checks configured"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Health Check Overview$(NC)"
	@echo "$(YELLOW)===================$(NC)"
	@for stack in $(STACKS); do \
		echo "$(BLUE)$$stack stack health:$(NC)"; \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) ps --format table --filter "status=running" | grep -E "(healthy|unhealthy)" || echo "No health checks configured"; \
		echo ""; \
	done
endif

cleanup: ## Clean up unused containers, networks, and images
	@echo "$(BLUE)Cleaning up Docker resources...$(NC)"
	@echo "$(YELLOW)Removing stopped containers...$(NC)"
	@docker container prune -f
	@echo "$(YELLOW)Removing unused networks...$(NC)"
	@docker network prune -f
	@echo "$(YELLOW)Removing unused images...$(NC)"
	@docker image prune -f
	@echo "$(YELLOW)Removing unused volumes (use with caution)...$(NC)"
	@read -p "Remove unused volumes? This may delete data! (y/N): " confirm && [ "$$confirm" = "y" ] && docker volume prune -f || echo "Skipping volume cleanup"
	@echo "$(GREEN)Cleanup completed$(NC)"

cleanup-aggressive: ## Aggressive cleanup including unused images with no containers
	@echo "$(RED)WARNING: This will remove ALL unused images!$(NC)"
	@read -p "Continue with aggressive cleanup? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) cleanup
	@echo "$(YELLOW)Removing all unused images...$(NC)"
	@docker image prune -a -f
	@echo "$(GREEN)Aggressive cleanup completed$(NC)"

backup: ## Backup configurations and optionally data (STACK=name for specific stack)
	@echo "$(BLUE)Creating backup...$(NC)"
	@mkdir -p $(BACKUP_DIR)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(YELLOW)Backing up $(STACK) stack configuration...$(NC)"; \
		tar -czf $(BACKUP_DIR)/$(STACK)_config_$(TIMESTAMP).tar.gz -C $(STACKS_DIR) $(STACK)/; \
		echo "$(GREEN)Backup completed: $(BACKUP_DIR)/$(STACK)_config_$(TIMESTAMP).tar.gz$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(YELLOW)Backing up all stack configurations...$(NC)"
	@tar -czf $(BACKUP_DIR)/stacks_config_$(TIMESTAMP).tar.gz -C $(PWD) stacks/
	@echo "$(YELLOW)Backing up Docker volumes...$(NC)"
	@docker run --rm -v dockge_backup:/backup -v $(PWD)/$(BACKUP_DIR):/host alpine sh -c "tar -czf /host/volumes_$(TIMESTAMP).tar.gz -C /backup ." 2>/dev/null || echo "$(YELLOW)No named volumes found or backup failed$(NC)"
	@echo "$(GREEN)Backup completed: $(BACKUP_DIR)/stacks_config_$(TIMESTAMP).tar.gz$(NC)"
endif

list-backups: ## List available backups
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -la $(BACKUP_DIR)/ 2>/dev/null || echo "$(YELLOW)No backups found$(NC)"

restore: ## Restore from backup (specify BACKUP_FILE=filename)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "$(RED)Error: Please specify BACKUP_FILE=filename$(NC)"; \
		echo "$(YELLOW)Example: make restore BACKUP_FILE=stacks_config_20240101_120000.tar.gz$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(BACKUP_DIR)/$(BACKUP_FILE)" ]; then \
		echo "$(RED)Error: Backup file $(BACKUP_DIR)/$(BACKUP_FILE) not found$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Restoring from $(BACKUP_FILE)...$(NC)"
	@read -p "This will overwrite current stack configurations. Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@tar -xzf $(BACKUP_DIR)/$(BACKUP_FILE) -C $(PWD)
	@echo "$(GREEN)Restore completed$(NC)"

update: ## Pull latest images and restart (STACK=name for specific stack)
ifdef STACK
	@echo "$(BLUE)Updating $(STACK) stack...$(NC)"
	@$(MAKE) pull STACK=$(STACK) && $(MAKE) restart STACK=$(STACK)
	@echo "$(GREEN)$(STACK) update completed$(NC)"
else
	@echo "$(BLUE)Updating all stacks...$(NC)"
	@$(MAKE) pull restart
	@echo "$(GREEN)Update completed$(NC)"
endif

dev-mode: ## Start stacks in development mode (non-detached)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(BLUE)Starting $(STACK) stack in development mode...$(NC)"; \
		echo "$(YELLOW)Press Ctrl+C to stop$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) up; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Starting all stacks in development mode...$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop all stacks$(NC)"
	@for stack in $(STACKS); do \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) up & \
		sleep 3; \
	done; \
	wait
endif

quick-status: ## Quick status check (just running containers)
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -1
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -v NAMES | sort || echo "$(YELLOW)No containers running$(NC)"

quick-restart: ## Quick restart without dependency order (STACK=name for specific stack)
ifdef STACK
	@if echo "$(STACKS)" | grep -wq "$(STACK)"; then \
		echo "$(BLUE)Quick restart of $(STACK) stack...$(NC)"; \
		cd $(STACKS_DIR)/$(STACK) && $(COMPOSE) restart; \
		echo "$(GREEN)$(STACK) quick restart completed$(NC)"; \
	else \
		echo "$(RED)Error: Stack '$(STACK)' not found. Available: $(STACKS)$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Quick restart of all stacks...$(NC)"
	@for stack in $(STACKS); do \
		cd $(STACKS_DIR)/$$stack && $(COMPOSE) restart & \
	done; \
	wait
	@echo "$(GREEN)Quick restart completed$(NC)"
endif

list-stacks: ## List all discovered stacks
	@echo "$(BLUE)Discovered stacks:$(NC)"
	@for stack in $(STACKS); do \
		echo "  $(GREEN)$$stack$(NC)"; \
	done
