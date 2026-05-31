# portainer-homelab-catalog

A Portainer App Templates catalog for homelab self-hosted stacks, organised by category.

## Available stacks

### 🖥️ System

| Stack | Description |
|-------|-------------|
| [Watchtower](system/watchtower/docker-compose.yml) | Automatically update running Docker containers to the latest image version |

### 🌐 Network

| Stack | Description |
|-------|-------------|
| [UniFi Controller](network/unifi-controller/docker-compose.yml) | Ubiquiti UniFi Network Management Controller for managing UniFi devices |

### 🎬 Media

| Stack | Description |
|-------|-------------|
| [Plex Media Server](media/plex/docker-compose.yml) | Stream your media library to any device. Uses `qnet-static-bond0-0094fd` with a fixed MAC address. |

### 📊 Monitoring

| Stack | Description |
|-------|-------------|
| [Prometheus & Loki](monitoring/prometheus-loki/docker-compose.yml) | Full monitoring stack: Prometheus (metrics) + Loki (logs) + Promtail + Grafana |

## Usage

### Add to Portainer

1. In Portainer, go to **Settings → App Templates**.
2. Set the **URL** to:
   ```
   https://raw.githubusercontent.com/calavia-org/portainer-homelab-catalog/main/portainer/templates/v3/templates.json
   ```
3. Save settings and navigate to **App Templates** to deploy any stack.

## Repository structure

```
portainer/
└── templates/
    └── v3/
        └── templates.json             # Portainer App Templates catalog (v3)
system/
└── watchtower/
    └── docker-compose.yml
network/
└── unifi-controller/
    └── docker-compose.yml
media/
└── plex/
    └── docker-compose.yml
monitoring/
└── prometheus-loki/
    ├── docker-compose.yml
    ├── prometheus.yml                 # Prometheus scrape configuration
    ├── loki-config.yml               # Loki storage and schema configuration
    └── promtail-config.yml           # Promtail log scraping configuration
```
