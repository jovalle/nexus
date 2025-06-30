<div align="center">

<img src="./nexus.jpeg" height="400px"/>

# Nexus

A self-hosted citadel

</div>

## Getting Started

```sh
git clone github.com/jovalle/nexus
cd nexus
docker compose up -d
```

In Dockge, add each stack directory from this repo as a new stack. Each stack contains its own `docker-compose.yml` and `.env` file.

**Note:** Changes to a stack's `.env` only affect containers in that stack referencing those variables.

## Stacks Structure

```sh
stacks/
├── core/
│   ├── .env
│   └── compose.yaml
├── database/
│   ├── .env
│   └── compose.yaml
├── log/
│   ├── .env
│   └── compose.yaml
├── media/
│   ├── .env
│   └── compose.yaml
├── server/
│   ├── .env
│   └── compose.yaml
```

## Stacks

This repository is structured for use with [Dockge](https://dockge.kuma.pet/), which provides a web UI for managing Docker Compose stacks:

### 🐋 Root Stack

* ⚓ [Dockge](https://github.com/louislam/dockge) – Web UI tool to spin up and orchestrate Docker “stacks” from consolidated configs.

### 🔗 Core Stack

* 🛡️ [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) – Network-wide ad/blocking DNS server.
* 🐳 [docker-socket-proxy](https://github.com/spotify/docker-socket-proxy) – Exposes docker socket securely.
* 🏠 [Homepage](https://github.com/getHomepage/homepage) – Central landing page to quickly glance and navigate services.
* 🚢 [Portainer](https://www.portainer.io) – GUI for managing Docker environments & stacks.
* 🚦 [Traefik](https://traefik.io) – Dynamic reverse-proxy & load-balancer for HTTP/TCP services.

### 🗄️ Database Stack

* 🍷 [MariaDB](https://mariadb.org) – MySQL-compatible relational database.
* 💻 [pgAdmin](https://www.pgadmin.org) – Web-based GUI to manage PostgreSQL instances.
* 🐘 [PostgreSQL](https://www.postgresql.org) – Reliable relational SQL database.
* 🧧 [Redis](https://redis.io) – In-memory key-value store for caching and fast data access.
* 💽 [Valkey](https://github.com/louislam/valkey) – A successor of Redis with notable gains in performance and usability.

### 📋 Log Stack

* 📊 [Grafana](https://grafana.com) – Visualizations & dashboards for metrics.
* 📜 [Loki](https://grafana.com/oss/loki) – Log aggregation system designed to work with Grafana.
* 📈 [Prometheus](https://prometheus.io) – Time-series database & alerting.
* 🖋️ [Promtail](https://grafana.com/oss/loki) – Agent to collect & ship logs into Loki.

### 🎥 Media Stack

* 🎙️ [Bazarr](https://www.bazarr.media) – Subtitle management for Sonarr/Radarr.
* 🧲 [Gluetun](https://github.com/qdm12/gluetun) – VPN client container for routing other media services securely.
* 🎵 [Lidarr](https://lidarr.audio) – Music collection curator.
* 🗂️ [Profilarr](https://wiki.servarr.com/profilarr) – Manages metadata & images for your media collections.
* 📦 [Prowlarr](https://wiki.servarr.com/prowlarr) – Indexer manager for Sonarr/Radarr.
* 📥 [qBittorrent](https://www.qbittorrent.org) – BitTorrent client with a built-in web UI.
* 🎬 [Radarr](https://radarr.video) – Movie collection curator.
* 📦 [SABnzbd](https://sabnzbd.org) – Usenet downloader with a simple web interface.
* 📺 [Sonarr](https://sonarr.tv) – TV series collection curator.
* 🔍 [Tautulli](https://github.com/Tautulli/Tautulli) – Monitoring & analytics for your Plex server.
* 🛎️ [Unpackerr](https://github.com/JoshHowland/unpackerr) – Automatically extracts archives for Sonarr/Radarr.
* 👁️ [Watchtower](https://github.com/containrrr/watchtower) – Automatic Docker container updates.
* 🗂️ [Profilarr](https://wiki.servarr.com/profilarr) – Manages metadata & images for your media collections.
* 📨 [Overseerr](https://overseerr.dev) – Requests and manages media for Plex & Jellyfin users.

### 🖥️ Server Stack

* 📸 [Immich](https://immich.app) – Personal photo and video backup and gallery.
* 🤖 [Immich Machine Learning](https://github.com/immich-app/immich-machine-learning) – Machine learning service for image recognition in Immich.
* 🍿 [Jellyfin](https://jellyfin.org) – Open source media system for managing and streaming media.
* 🎶 [Navidrome](https://www.navidrome.org) – Music server for streaming FLAC/MP3 collections.
* ☁️ [Nextcloud](https://nextcloud.com) – Self-hosted file synchronization and sharing platform.
* 🎬 [Plex](https://www.plex.tv) – Media server for organizing and streaming movies and TV shows.
* 🔄 [Syncthing](https://syncthing.net) – Continuous file synchronization across devices.

### 🛠️ Tools Stack

* 📄 [Apache Tika](https://tika.apache.org) – Text extraction from documents such as PDF and DOCX.
* 📚 [Gotenberg](https://thecodingmachine.github.io/gotenberg) – API for converting HTML and Markdown to PDF.
* 📰 [Miniflux](https://miniflux.app) – Minimalist self-hosted RSS reader.
* 🗃️ [Paperless-NGX](https://github.com/paperless-ngx/paperless-ngx) – Document management system for scanning, indexing, and archiving.

### 🛡️ Security Stack

* 🔐 [Authentik](https://goauthentik.io) – Identity provider for single sign-on and user management.
* 👷 [Authentik-Worker](https://goauthentik.io/docs/) – Background job processor for Authentik.
* 🏰 [CrowdSec](https://crowdsec.net) – Collaborative intrusion-prevention system for blocking malicious IPs.

## Best Practices

* Keep sensitive information (like passwords) in the `.env` files and avoid committing secrets to version control.
* Only modify the `.env` for the stack you wish to change; this ensures isolated configuration.
* Use Dockge/Portainer to monitor logs and Dockge to manage updates for each stack.
