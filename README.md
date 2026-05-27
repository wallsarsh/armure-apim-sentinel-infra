# Business Apps — Frappe Development Environment

This project provides a **fully containerized Frappe development environment** using Docker.  
Nothing is installed on the host OS except Docker itself.

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/) (Engine 24+ with Docker Compose v2)
- [Git](https://git-scm.com/)
- At least **4 GB** of available RAM for Docker

> **Note for VS Code users:** Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) for the best experience — the project is fully compatible with the `.devcontainer` setup from [frappe/frappe_docker](https://github.com/frappe/frappe_docker).

---

## Quick Start

### 1. Start the Docker services

```bash
cd /home/prolinux/dev/armure-apim-governance/armure-apim-sentinel
docker compose up -d
```

This starts:
- **MariaDB** — database server
- **Redis Cache & Queue** — caching and background job queue
- **Frappe Bench** — the development container (runs `sleep infinity`)

### 2. Initialize the Frappe Bench

Once all services are healthy, initialize the bench inside the container:

```bash
docker compose exec frappe bash
```

Inside the container, run:

```bash
cd /workspace/development
bash init.sh
```

This will:
1. Create a Frappe bench (`armure-apim/`)
2. Download Frappe framework (version-16) and any apps listed in `development/apps.json`
3. Configure database and Redis connections
4. Create a development site (`apim.localhost`)
5. Enable **developer mode**

### 3. Start the development server

```bash
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench start"
```

Or for a lightweight web-only server:

```bash
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench serve --port 8000"
```

Visit **[http://localhost:8000](http://localhost:8000)** and log in with:
- **Username:** `Administrator`
- **Password:** `admin` (set via `ADMIN_PASSWORD` in `.env`)

---

## Creating a Custom App

```bash
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench new-app my_custom_app"
```

Then install it on your site:

```bash
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench --site apim.localhost install-app my_custom_app"
```

Your custom app code lives at `development/armure-apim/apps/my_custom_app/` and is persisted on the host.

---

## Adding More Apps

Edit `development/apps.json` to add Frappe apps you want to install. For example:

```json
[
  {
    "url": "https://github.com/frappe/frappe",
    "branch": "version-16"
  },
  {
    "url": "https://github.com/frappe/erpnext",
    "branch": "version-16"
  }
]
```

Then rebuild the bench with `bash init.sh` (it skips steps that already exist).

---

## Useful Commands

| Action | Command |
|--------|---------|
| Start services | `docker compose up -d` |
| Stop services | `docker compose down` |
| View logs | `docker compose logs -f frappe` |
| Open shell in container | `docker compose exec frappe bash` |
| Run bench command | `docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench <command>"` |
| Restart after changes | `docker compose restart frappe` |

---

## Project Structure

```
business-apps/
├── docker-compose.yml       # Docker Compose services
├── .env                     # Environment variables (DB passwords, ports)
├── .gitignore               # Git ignore rules
├── README.md                # This file
└── development/             # Working directory (mounted into container)
    ├── apps.json            # Apps to install in the bench
    ├── init.sh              # Bench initialization script
    └── armure-apim/        # Created by init.sh — the Frappe bench
```

---

## Configuration

Edit `.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `MYSQL_ROOT_PASSWORD` | `123` | MariaDB root password |
| `MARIADB_PORT` | `3306` | MariaDB host port |
| `BENCH_NAME` | `armure-apim` | Bench directory name |
| `SITE_NAME` | `apim.localhost` | Default site name |
| `ADMIN_PASSWORD` | `admin` | Administrator password |
| `FRAPPE_BRANCH` | `version-16` | Frappe version branch |
| `DB_TYPE` | `mariadb` | Database type (mariadb/postgres) |
| `BENCH_WEB_PORT` | `8000` | Web server host port |
| `BENCH_SOCKETIO_PORT` | `9000` | SocketIO host port |

---

## Release Container Build Process

cd build/docker

``` bash
docker build --no-cache \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16  \
  --build-arg=SENTINEL_BRANCH=main  \
  --build-arg=SENTINEL_REPO='https://[deploy-token-user]:[deploy-token-value]@gitlab.com/simplified-it/armure-apim/governance/armure-apim-sentinel.git'  \ 
  --tag=armure-apim-sentinel:2.4   --file=images/production/Containerfile .

docker image ls
```

## Troubleshooting

**"Can't connect to MariaDB"**  
Make sure MariaDB is healthy: `docker compose ps`. Wait a few seconds and retry.

**Bench init fails on git clone**  
Ensure `development/apps.json` has valid repository URLs and branches.

**Port already in use**  
Change `BENCH_WEB_PORT` or `MARIADB_PORT` in `.env` and restart.

**Permission denied when running init.sh**  
Run inside the container: `docker compose exec frappe bash` then `bash init.sh`.

---

## References

- [Frappe Framework Documentation](https://frappeframework.com/docs)
- [frappe_docker on GitHub](https://github.com/frappe/frappe_docker)
- [Frappe Community Forum](https://discuss.frappe.io/)
