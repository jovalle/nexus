<div align="center">

<img src=".github/assets/logo.png" height="400px"/>

# Nexus

![Uptime](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_uptime&style=flat&label=uptime) ![CPU Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_cpu_usage&style=flat&label=cpu) ![Memory Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_memory_usage&style=flat&label=memory) ![Containers](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_containers_running&style=flat&label=running)

</div>

## Overview

Born from consolidating numerous containers onto my TrueNAS server, this project aims to organize the growing (80+ services) catalog managed through a single root compose file with per-service directories, environment files, and a bash-based CLI.

## Quick Start

```bash
# Clone and enter
git clone https://github.com/jovalle/nexus.git && cd nexus

# Validate host requirements
./nexus preflight

# Prepare local defaults (.env + network)
./nexus network

# Review and fill in your environment
$EDITOR .env

# Run everything
./nexus up

# Run a single service
./nexus up plex
```

## Structure

```bash
nexus/
├── .env                  # Global environment variables (gitignored)
├── .env.example          # Template with placeholder values
├── archive/              # Retired service definitions
├── backups/              # Backup data (gitignored)
├── compose.yaml          # Root compose — includes all services
├── nexus                 # Bash CLI for stack operations
├── scripts/              # Maintenance scripts
├── services/
│   └── {name}/
│       ├── compose.yaml  # Service definition
│       └── .env          # Service-specific overrides (gitignored)
└── LICENSE
```

## Usage

All management goes through `./nexus`:

```bash
./nexus help            # Show available commands
./nexus preflight       # Validate host requirements
./nexus up [svc]        # Start service(s)
./nexus down [svc]      # Stop service(s)
./nexus restart [svc]   # Restart service(s)
./nexus logs [svc]      # Stream logs
./nexus ps [svc]        # Show container status
./nexus pull [svc]      # Pull updates and restart
```

## Configuration

Environment variables flow from two levels:

1. **Root `.env`** — shared values (paths, domain, timezone, credentials)
2. **`services/<name>/.env`** — service-specific overrides

See [.env.example](.env.example) for all available variables.

## License

MIT
