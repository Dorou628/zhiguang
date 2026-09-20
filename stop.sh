#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker compose --project-name resume-zhiguang down
