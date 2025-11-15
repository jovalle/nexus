<div align="center">

<img src=".github/assets/logo.png" height="400px"/>

# Nexus

![Node Uptime](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_uptime&style=flat&label=uptime) ![CPU Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_cpu_usage&style=flat&label=cpu) ![Memory Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_memory_usage&style=flat&label=memory) ![Docker Containers](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_containers_running&style=flat&label=running)

</div>

## ✨ Overview

Born from consolidating numerous containers onto my TrueNAS server, this project aims to organize the growing catalog using Docker Compose stacks.

## ⚠️ Disclaimer

**IMPORTANT**: Running custom commands and containers on TrueNAS SCALE is against the intent of iX-Systems and its developers. TrueNAS SCALE is designed to be managed through its web interface and official applications ecosystem.

**By using this project, you acknowledge that:**

- ⚠️ You are proceeding at your own risk
- 🚫 I hold no responsibility for any damage, data loss, or system instability incurred by the usage of this project
- 🛡️ This may void support from iX-Systems
- ⚙️ System updates may break custom configurations
- 🧪 You should proceed with caution and maintain proper backups

**Use this project only if you understand the risks and accept full responsibility for your system.**

## 🚀 Highlights

- 🚀 Push to `nx start` (😅) simplicity for deploying dozens of containers on a single host
- 🧰 Dockge & Portainer included for additional point-and-click controls
- 🧱 Clearly separated stacks (`app`, `media`, `data`, etc.) for modular upgrades
- 📊 First-class observability via Prometheus, Grafana, Loki, Dozzle, Beszel, & more!
- 🗂️ Monorepo structure keeps Compose services, env vars, and docs in one place with many improvements to come

## 📋 Best Practices

- 📂 Each stack ships with its own `compose.yaml` and `.env` file. Dockge auto-imports them on startup.
- 🔐 Keep sensitive values in the stack-specific `.env` files and never commit secrets to the repo.
- 🧩 Modify only the `.env` of the stack you intend to change to keep configurations isolated.
- ✨ Feel free to add, remove or modify stacks to your liking!
- ⚙️ Use `nx <command>` for everyday lifecycle tasks (start, stop, logs, backups, etc.).
- 📈 Monitor stack health via Beszel, Dockpeek, Dockge or Portainer.
- ♻️ By default, Watchtower will keep all deployed services up-to-date.
- 🧱 When adding new services, follow the existing folder pattern to keep stacks modular and easy to reason about.

## 🛠️ Getting Started

> 📖 **Detailed Setup Guide**: See [SETUP.md](SETUP.md) for comprehensive setup instructions and troubleshooting.

### Quick Setup

For first-time setup with automated environment configuration:

1. Clone the repository:

   ```sh
   git clone https://github.com/jovalle/nexus
   cd nexus
   ```

2. Run the automated setup (installs Homebrew and required tools):

   ```sh
   sudo ./scripts/setup.sh jay  # Replace 'jay' with your username
   # Or set via environment variable:
   # sudo NEXUS_USER=jay ./scripts/setup.sh
   ```

   This will:
   - Install Homebrew (Linuxbrew) configured for the specified user
   - Install required tools like `direnv`, `fzf`, `jq`, and `yq`
   - Set up `direnv` for automatic environment loading
   - Configure tab completion for the `nx` command

3. Allow direnv and activate the environment:

   ```sh
   direnv allow .
   ```

   The `nx` command will now be in your PATH with intelligent tab completion!

4. Review `.env` files inside each stack and adjust values to match your environment (paths, credentials, network details).

5. Launch everything:

   ```sh
   nx start
   ```

   > 🧬 Migrating to/from TrueNAS? Change `DATA_PATH` and Nexus will feel instantly familiar.

6. Open Dockge (exposed via the root stack) to configure and monitor stacks.

> 🛠️ Prefer Portainer? It is included under the `core` stack. Open its web UI, import the Compose files, and manage stacks from there.

### Manual Setup

If you prefer manual installation or already have the required tools:

1. Clone the repository:

   ```sh
   git clone https://github.com/jovalle/nexus
   cd nexus
   ```

2. Install prerequisites:

   ```sh
   # Install direnv (for automatic environment loading)
   brew install direnv

   # Install fzf (for enhanced tab completion)
   brew install fzf

   # Add direnv hook to your shell
   echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc  # for zsh
   # or
   echo 'eval "$(direnv hook bash)"' >> ~/.bashrc  # for bash

   # Reload your shell
   source ~/.zshrc  # or source ~/.bashrc
   ```

3. Allow direnv to load the environment:

   ```sh
   direnv allow .
   ```

4. Review `.env` files and adjust as needed.

5. Launch stacks using the `nx` command:

   ```sh
   nx start
   ```

### nx CLI Features

The `nx` command provides a powerful interface for managing your Docker stacks:

- **Tab Completion**: Press `Tab` after typing `nx` to see available commands and stacks
- **fzf Integration**: Press `Ctrl+Space` for interactive fuzzy-search selection of commands
- **Dynamic Help**: Command descriptions are auto-generated from the script itself
- **Stack-aware**: Automatically detects stacks in the `stacks/` directory

Example commands:

```sh
nx help              # Show all available commands
nx list              # List all available stacks
nx start             # Start all stacks
nx start media       # Start only the media stack
nx stop core         # Stop the core stack
nx logs app -f       # Follow logs for app stack
nx status            # Show status of all stacks
nx update            # Update all containers to latest versions
nx fmt               # Update README with current service listings
nx backup            # Create backup of all configurations
nx validate          # Validate all compose files
```

### Updating

Update the service listings in README:

```sh
nx fmt
```

Update containers to latest versions:

```sh
nx update
```

Automated updates are handled by [Watchtower](https://containrrr.dev/watchtower/).

## 📁 Project Structure

```text
stacks/
├── app/
│   ├── .env
│   └── compose.yaml
├── core/
│   ├── .env
│   └── compose.yaml
...
├── log/
│   ├── .env
│   └── compose.yaml
```

Stacks are intentionally scoped so you can update, pause, or extend categories independently.

## 🏗️ Stack/Service Lineup

This repository is structured for use with [Dockge](https://dockge.kuma.pet/), offering a clean UI to deploy and maintain Compose stacks:

### 🐋 Root

[**Dockge**](https://dockge.kuma.pet/) - Docker GUI

### 🧩 App

**Excalidraw** • **Mytabs** • **Omni-tools** • **Searxng**

### 🔧 Core

**Adguard** - Ad-Blocking DNS Server • **Authelia** • **Docker-socket-proxy** • **Dockpeek** • **Dozzle** • **Homepage** • **Portainer** - Container Management • **Tailscale** • **Traefik** - Reverse proxy for exposing apps via HTTPS • **Trala** • **Watchtower**

### 💾 Data

**Gotenberg** • **Immich** - Photo management and backup • **Immich-machine-learning** • **Mariadb** • **Nextcloud** - Cloud storage and collaboration • **Paperless** - Paperless Document Management • **Pgadmin** - PostgreSQL Management Tool • **Postgres** • **Redis** • **Syncthing** - File synchronization • **Tika** • **Valkey**

### 📊 Log

**Apprise** • **Beszel** - Lightweight server monitoring platform • **Beszel-agent** • **Cadvisor** • **Glances** - System Monitoring Tool • **Grafana** - Metrics Visualizer • **Harborguard** • **Intel-gpu-exporter** • **Kromgo** • **Loggifly** • **Loki** • **Node-exporter** • **Ntfy** • **Plex-exporter** • **Prometheus** - Metrics collection • **Promtail** • **Smartctl-exporter**

### 🎬 Media

**Agregarr** • **Audiodeck** • **Bazarr** - Subtitle Curator • **Flaresolverr** • **Gluetun** - VPN client for containers • **Jellyfin** - Media Server • **Lidarr** - Personal Music Curator • **Navidrome** - Personal Music Streamer • **Overseerr** - Media Server Request Management • **Plex** - Media Server • **Profilarr** - Profile Management for *arrs • **Prowlarr** - Indexer Manager for *arrs • **Qbittorrent** - BitTorrent client for ISOs • **Radarr** - Personal Movie Curator • **Sabnzbd** - Binary Newsreader • **Sonarr** - Personal Series Curator • **Tautulli** - Media Server Companion • **Unpackerr** • **Wizarr**
