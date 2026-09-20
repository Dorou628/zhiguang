#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker info >/dev/null
[ -f .env ] || cp .env.example .env
if [ "${1:-}" = '--rebuild' ]; then docker compose --project-name resume-zhiguang build; fi
docker compose --project-name resume-zhiguang up --detach --wait --wait-timeout 480
printf '\nOpen http://'
docker compose --project-name resume-zhiguang port frontend 80
printf "Demo login: demo@example.com / DemoPass123!\n"
