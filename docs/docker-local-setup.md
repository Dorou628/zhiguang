# Docker local setup

This repository now includes a `docker-compose.yml` that can start the backend dependencies for local development, and it can also start the frontend when the `full-stack` profile is enabled.

## What it starts

- MySQL 8
- Redis 7
- Kafka (KRaft mode)
- Elasticsearch
- Canal

The backend and frontend services are included as an optional `full-stack` profile.

## Common commands

Start only middleware and keep debugging the backend in IDEA:

```bash
docker compose up -d
```

Start everything, including the backend container:

```bash
docker compose --profile full-stack up -d --build
```

Stop all containers:

```bash
docker compose down
```

Stop and remove data volumes:

```bash
docker compose down -v
```

## Ports

- MySQL: `3306`
- Redis: `6379`
- Kafka host listener: `9092`
- Elasticsearch: `9200`
- Canal: `11111`
- Backend: `8080` when `full-stack` is enabled
- Frontend: `5173` when `full-stack` is enabled

## Notes

- `docker compose up -d` is the easiest path for day-to-day development. Your local backend can keep using the existing `application.yml`.
- The backend container uses the `docker` Spring profile from `src/main/resources/application-docker.yml`.
- The frontend container is built from `D:\WebApp\zhiguang\zhiguang_fe-main` and served by Nginx. Requests under `/api` are proxied to the backend container.
- MySQL initialization scripts only run when the MySQL data volume is first created. If you need a clean reset, use `docker compose down -v`.
- The Elasticsearch image here is the official single-node image. If you rely on the IK analyzer for search testing, you may want to swap it for an IK-enabled image later.
