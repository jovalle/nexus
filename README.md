<div align="center">

<img src="./nexus.jpeg" height="400px"/>

# Nexus

A self-hosted citadel. Batteries included.

</div>

## Getting Started

```sh
git clone github.com/jovalle/nexus
cd nexus
make start
```

Each stack contains its own `compose.yml` and `.env` file which should be auto-imported by Dockge.

If Dockge is not your cup of tea, `Portainer` is also included.

**Note:** Changes to a stack's `.env` only affect containers in that stack referencing those variables.

## Stacks Structure

```sh
stacks/
├── app/
│   ├── .env
│   └── compose.yaml
├── core/
│   ├── .env
│   └── compose.yaml
├── data/
│   ├── .env
│   └── compose.yaml
├── media/
│   ├── .env
│   └── compose.yaml
├── observability/
│   ├── .env
│   └── compose.yaml
```

## Stacks

This repository is structured for use with [Dockge](https://dockge.kuma.pet/), which provides a web UI for managing Docker Compose stacks:

### 🐋 _ (Root)

* ⚓ [Dockge](https://github.com/louislam/dockge) – Web UI tool to spin up and orchestrate Docker “stacks” from consolidated configs.

### 📱 App

* 📸 [Immich](https://immich.app) – Personal photo and video backup and gallery.
* 🤖 [Immich Machine Learning](https://github.com/immich-app/immich-machine-learning) – Machine learning service for image recognition in Immich.
* 🍿 [Jellyfin](https://jellyfin.org) – Open source media system for managing and streaming media.
* 🎶 [Navidrome](https://www.navidrome.org) – Music server for streaming FLAC/MP3 collections.
* ☁️ [Nextcloud](https://nextcloud.com) – Self-hosted file synchronization and sharing platform.
* 🎬 [Plex](https://www.plex.tv) – Media server for organizing and streaming movies and TV shows.
* 🔄 [Syncthing](https://syncthing.net) – Continuous file synchronization across devices.

### 🔗 Core

* 🛡️ [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) – Network-wide ad/blocking DNS server.
* 🐳 [docker-socket-proxy](https://github.com/spotify/docker-socket-proxy) – Exposes docker socket securely.
* 🏠 [Homepage](https://github.com/getHomepage/homepage) – Central landing page to quickly glance and navigate services.
* 🚢 [Portainer](https://www.portainer.io) – GUI for managing Docker environments & stacks.
* 🚦 [Traefik](https://traefik.io) – Dynamic reverse-proxy & load-balancer for HTTP/TCP services.

### 🗄️ Data

* 🍷 [MariaDB](https://mariadb.org) – MySQL-compatible relational database.
* 💻 [pgAdmin](https://www.pgadmin.org) – Web-based GUI to manage PostgreSQL instances.
* 🐘 [PostgreSQL](https://www.postgresql.org) – Reliable relational SQL database.
* 🧧 [Redis](https://redis.io) – In-memory key-value store for caching and fast data access.
* 💽 [Valkey](https://github.com/louislam/valkey) – A successor of Redis with notable gains in performance and usability.

### 📺 Media

* 📝 [Bazarr](https://github.com/morpheus65535/bazarr) – Subtitle manager for Sonarr, Radarr and Lidarr; automates searching and syncing of subtitles across your media libraries.
* 🌩️ [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) – Proxy server to bypass Cloudflare protections; enables headless browsers and scripts to solve challenges and access protected web content.
* 🛡️ [Gluetun](https://github.com/qdm12/gluetun) – VPN client container supporting multiple providers, DNS-over-TLS, ad-blocking and firewall rules to secure and privatize all traffic.
* 🎵 [Lidarr](https://github.com/lidarr/Lidarr) – Music collection manager for Usenet and BitTorrent; monitors artist releases and organizes new tracks in your library.
* 🛎️ [Overseerr](https://github.com/sct/overseerr) – User-friendly media request management for movies and TV; integrates with Plex, Sonarr and Radarr for automated approval workflows.
* 📑 [Profilarr](https://github.com/OMGDON203/profilarr) – Profile synchronizer for Sonarr, Radarr and Lidarr; ensures consistent indexer profiles and search settings across all apps.
* 🔍 [Prowlarr](https://github.com/Prowlarr/Prowlarr) – Central indexer manager for Usenet and torrent trackers; streamlines setup of indexers for Sonarr, Radarr, Lidarr and more.
* 📥 [qBittorrent](https://www.qbittorrent.org/) – Lightweight, cross-platform BitTorrent client with Web UI, RSS feed support and integrated search for peer-to-peer transfers.
* 🎬 [Radarr](https://github.com/Radarr/Radarr) – Movie collection manager for Usenet and BitTorrent; monitors film releases and organizes your movie library.
* 📡 [SABnzbd](https://sabnzbd.org/) – Python-based Usenet client; automates NZB handling, queuing and archive extraction for hassle-free binary newsreading.
* 📺 [Sonarr](https://github.com/Sonarr/Sonarr) – TV series manager that monitors RSS feeds for new episodes, organizes and renames shows using your configured indexers.
* 📊 [Tautulli](https://github.com/Tautulli/Tautulli) – Plex Media Server monitoring and analytics; tracks usage, sends notifications and generates customizable reports.
* 📦 [Unpackerr](https://github.com/htpcjunkie/unpackerr) – Archive automation tool; watches completed transfers, extracts archives and returns processed items to your client.
* 🧙 [Wizarr](https://github.com/wizarrrr/wizarr) – Automated invitation and onboarding system for Plex, Jellyfin and Emby; simplifies user invites and guides them through setup.

### 📋 Observability

* 📊 [Grafana](https://grafana.com) – Visualizations & dashboards for metrics.
* 📜 [Loki](https://grafana.com/oss/loki) – Log aggregation system designed to work with Grafana.
* 📈 [Prometheus](https://prometheus.io) – Time-series database & alerting.
* 🖋️ [Promtail](https://grafana.com/oss/loki) – Agent to collect & ship logs into Loki.

### 🛡️ Security

* 🔐 [Authentik](https://goauthentik.io) – Identity provider for single sign-on and user management.
* 🏰 [CrowdSec](https://crowdsec.net) – Collaborative intrusion-prevention system for blocking malicious IPs.

### 🛠️ Utility

* 📄 [Apache Tika](https://tika.apache.org) – Text extraction from documents such as PDF and DOCX.
* 📚 [Gotenberg](https://thecodingmachine.github.io/gotenberg) – API for converting HTML and Markdown to PDF.
* 📰 [Miniflux](https://miniflux.app) – Minimalist self-hosted RSS reader.
* 🗃️ [Paperless-NGX](https://github.com/paperless-ngx/paperless-ngx) – Document management system for scanning, indexing, and archiving.

## Best Practices

* Keep sensitive information (like passwords) in the `.env` files and avoid committing secrets to version control.
* Only modify the `.env` for the stack you wish to change; this ensures isolated configuration.
* Use Dockge/Portainer to monitor logs and Dockge to manage updates for each stack.
* Included `Makefile` can make multi-stack operations a breeze (e.g. `make tail`)
