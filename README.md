# Nexus

Docker Compose service stack for a home server. 80+ services managed through a single root compose file with per-service directories, environment files, and a `just`-based CLI.

## Quick Start

```bash
# Clone and enter
git clone https://github.com/jovalle/nexus.git && cd nexus

# Run setup (installs just, docker, creates network, etc.)
./setup.sh            # interactive
./setup.sh --auto     # opinionated defaults

# Copy and fill in your environment
cp .env.example .env

# Start everything
just up

# Start a single service
just up plex
```

## Structure

```
nexus/
├── compose.yaml          # Root compose — includes all services
├── .env                  # Global environment variables (gitignored)
├── .env.example          # Template with placeholder values
├── justfile              # Task runner recipes
├── setup.sh              # Host provisioning script
├── services/
│   └── {name}/
│       ├── compose.yaml  # Service definition
│       └── .env          # Service-specific overrides (gitignored)
├── scripts/              # Maintenance scripts
├── archive/              # Retired service definitions
└── backups/              # Backup data (gitignored)
```

## Usage

All management goes through `just`:

```bash
just              # List all recipes
just up [svc]     # Start service(s)
just down [svc]   # Stop service(s)
just restart svc  # Restart a service
just logs svc     # Tail logs
just status       # Show running containers
just retire svc   # Archive a service
```

Run `just --list` for the full recipe list.

## Configuration

Environment variables flow from two levels:

1. **Root `.env`** — shared values (paths, domain, timezone, credentials)
2. **`services/<name>/.env`** — service-specific overrides

See [.env.example](.env.example) for all available variables.

## License

MIT
