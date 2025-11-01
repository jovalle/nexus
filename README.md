<div align="center">

<img src=".github/assets/logo.png" height="400px"/>

# Nexus

![Node Uptime](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_uptime&style=flat&label=uptime) ![CPU Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_cpu_usage&style=flat&label=cpu) ![Memory Usage](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_memory_usage&style=flat&label=memory) ![Docker Containers](https://img.shields.io/endpoint?url=https://stat.techn.is/query?metric=nexus_containers_running&style=flat&label=running)

</div>

## ✨ Overview

Born from consolidating numerous containers onto my TrueNAS server, this project aims to organize the growing catalog using Docker Compose stacks.

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

### Install

1. Clone the repository:

   ```sh
   git clone https://github.com/jovalle/nexus
   cd nexus
   ./nx alias
   ```

2. Review `.env` files inside each stack and adjust values to match your environment (paths, credentials, network details).

3. Launch everything:

   ```sh
   nx start
   ```

   > 🧬 Migrating to/from TrueNAS? Change `DATA_PATH` and Nexus will feel instantly familiar.

4. Open Dockge (exposed via the root stack) to configure and monitor stacks.

> 🛠️ Prefer Portainer? It is included under the `core` stack. Open its web UI, import the Compose files, and manage stacks from there.

### Updating

Manual refresh:

```sh
nx update
```

Automated updates via [Watchtower](https://containrrr.dev/watchtower/).

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

| Service | Purpose | Notes |
|---------|---------|-------|
| [Dockge](https://github.com/louislam/dockge) | Web UI tool to spin up and orchestrate Docker "stacks" from consolidated configs | - |

### 🧩 App

| Service | Purpose | Notes |
|---------|---------|-------|
| [Excalidraw](https://excalidraw.com) | Collaborative whiteboard for sketching infrastructure ideas | - |
| [MyTabs](https://github.com/louislam/its-mytabs) | Handy web UI for storing and reading guitar tabs | - |
| [Omni Tools](https://github.com/iib0011/omni-tools) | Swiss-army web toolbox for quick conversions and utilities | - |

### 🔗 Core

| Service | Purpose | Notes |
|---------|---------|-------|
| [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) | Network-wide ad/blocking DNS server | - |
| [Authelia](https://www.authelia.com/) | Single sign-on, MFA, and access policies for protected services | - |
| [Docker Socket Proxy](https://github.com/tecnativa/docker-socket-proxy) | Exposes docker socket securely | - |
| [Dockpeek](https://github.com/dockpeek/dockpeek) | Container inventory explorer with resource insights | - |
| [Dozzle](https://github.com/amir20/dozzle) | Realtime container log streaming from the browser | - |
| [Homepage](https://gethomepage.dev/) | Central landing page to quickly glance and navigate services | - |
| [Portainer](https://www.portainer.io) | GUI for managing Docker environments & stacks | - |
| [Tailscale](https://tailscale.com/) | Mesh VPN for remote access into the homelab | - |
| [Traefik](https://traefik.io) | Dynamic reverse-proxy & load-balancer for HTTP/TCP services | - |
| [Watchtower](https://containrrr.dev/watchtower/) | Automated container image updates with optional health checks | - |

### 🗄️ Data

| Service | Purpose | Notes |
|---------|---------|-------|
| [Gotenberg](https://gotenberg.dev/) | API for converting HTML and Markdown to PDF | - |
| [Immich](https://immich.app) | Personal photo and video backup and gallery | - |
| [Immich Machine Learning](https://github.com/immich-app/immich-machine-learning) | Machine learning service for image recognition in Immich | - |
| [MariaDB](https://mariadb.org) | MySQL-compatible relational database | - |
| [Nextcloud](https://nextcloud.com) | Sync and collaboration hub for files, calendars, and contacts | - |
| [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | Document management system for scanning, indexing, and archiving | - |
| [pgAdmin](https://www.pgadmin.org) | Web-based GUI to manage PostgreSQL instances | - |
| [PostgreSQL](https://www.postgresql.org) | Reliable relational SQL database | - |
| [Redis](https://redis.io) | In-memory key-value store for caching and fast data access | - |
| [Syncthing](https://syncthing.net) | Continuous file synchronization across devices | - |
| [Apache Tika](https://tika.apache.org) | Text extraction from documents such as PDF and DOCX | - |
| [Valkey](https://github.com/louislam/valkey) | A successor of Redis with notable gains in performance and usability | - |

### 📊 Log

| Service | Purpose | Notes |
|---------|---------|-------|
| [Apprise](https://github.com/caronc/apprise) | Unified notification gateway triggered by alerting rules | - |
| [Beszel](https://www.beszel.dev/) & Agent | Lightweight server monitoring | - |
| [cAdvisor](https://github.com/google/cadvisor) | Container resource exporter feeding Prometheus | - |
| [Glances](https://nicolargo.github.io/glances/) | Web dashboard for realtime host log | - |
| [Grafana](https://grafana.com) | Visualizations & dashboards for metrics | - |
| [HarborGuard](https://github.com/harborguard/harborguard) | Container security cockpit tracking images, CVEs, and drifts | - |
| [Intel GPU Exporter](https://github.com/clambin/intel-gpu-exporter) | Prometheus exporter for Intel iGPU utilization | - |
| [Kromgo](https://github.com/kashalls/kromgo) | When-things-go-wrong status page powered by Prometheus data | - |
| [Loggifly](https://github.com/ClemCer/loggifly) | Keyword-driven log watcher with Apprise notifications | - |
| [Loki](https://grafana.com/oss/loki) | Log aggregation system designed to work with Grafana | - |
| [Node Exporter](https://github.com/prometheus/node_exporter) | Host-level CPU, memory, and filesystem metrics | - |
| [Plex Exporter](https://github.com/timothystewart6/prometheus-plex-exporter) | Prometheus metrics for Plex activity | - |
| [Prometheus](https://prometheus.io) | Time-series database & alerting | - |
| [Promtail](https://grafana.com/oss/loki) | Agent to collect & ship logs into Loki | - |
| [SMARTctl Exporter](https://github.com/prometheus-community/smartctl_exporter) | Disk SMART health metrics for Prometheus | - |

### 📺 Media

| Service | Purpose | Notes |
|---------|---------|-------|
| [Bazarr](https://github.com/morpheus65535/bazarr) | Subtitle manager for Sonarr, Radarr and Lidarr; automates searching and syncing of subtitles across your media libraries | - |
| [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) | Proxy server to bypass Cloudflare protections; enables headless browsers and scripts to solve challenges and access protected web content | - |
| [Gluetun](https://github.com/qdm12/gluetun) | VPN client container supporting multiple providers, DNS-over-TLS, ad-blocking and firewall rules to secure and privatize all traffic | - |
| [Jellyfin](https://jellyfin.org) | Open source media system for managing and streaming media | - |
| [Lidarr](https://github.com/lidarr/Lidarr) | Music collection manager for Usenet and BitTorrent; monitors artist releases and organizes new tracks in your library | - |
| [Navidrome](https://www.navidrome.org) | Music server for streaming FLAC/MP3 collections | - |
| [Overseerr](https://github.com/sct/overseerr) | User-friendly media request management for movies and TV; integrates with Plex, Sonarr and Radarr for automated approval workflows | - |
| [Plex](https://www.plex.tv) | Media server for organizing and streaming movies and TV shows | - |
| [Profilarr](https://github.com/OMGDON203/profilarr) | Profile synchronizer for Sonarr, Radarr and Lidarr; ensures consistent indexer profiles and search settings across all apps | - |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | Central indexer manager for Usenet and torrent trackers; streamlines setup of indexers for Sonarr, Radarr, Lidarr and more | - |
| [qBittorrent](https://www.qbittorrent.org/) | Lightweight, cross-platform BitTorrent client with Web UI, RSS feed support and integrated search for peer-to-peer transfers | - |
| [Radarr](https://github.com/Radarr/Radarr) | Movie collection manager for Usenet and BitTorrent; monitors film releases and organizes your movie library | - |
| [SABnzbd](https://sabnzbd.org/) | Python-based Usenet client; automates NZB handling, queuing and archive extraction for hassle-free binary newsreading | - |
| [Sonarr](https://github.com/Sonarr/Sonarr) | TV series manager that monitors RSS feeds for new episodes, organizes and renames shows using your configured indexers | - |
| [Tautulli](https://github.com/Tautulli/Tautulli) | Plex Media Server monitoring and analytics; tracks usage, sends notifications and generates customizable reports | - |
| [Unpackerr](https://github.com/htpcjunkie/unpackerr) | Archive automation tool; watches completed transfers, extracts archives and returns processed items to your client | - |
| [Wizarr](https://github.com/wizarrrr/wizarr) | Automated invitation and onboarding system for Plex, Jellyfin and Emby; simplifies user invites and guides them through setup | - |
