#!/usr/bin/env bash
set -euo pipefail

repo_url="${REPO_URL:-https://github.com/demon-5656/shvirtd-example-python.git}"
app_dir="${APP_DIR:-/opt/shvirtd-example-python}"
backup_dir="${BACKUP_DIR:-/opt/backup}"
compose_file="${app_dir}/compose.yaml"

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi

  apt-get update
  apt-get install -y ca-certificates curl git gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

deploy_app() {
  install_docker

  if [ -d "${app_dir}/.git" ]; then
    git -C "${app_dir}" pull --ff-only
  else
    rm -rf "${app_dir}"
    git clone "${repo_url}" "${app_dir}"
  fi

  docker compose -f "${compose_file}" up -d --build
}

backup_db() {
  mkdir -p "${backup_dir}"
  set -a
  # shellcheck disable=SC1091
  source "${app_dir}/.env"
  set +a

  timestamp="$(date +%Y%m%d-%H%M%S)"
  network_name="$(docker network ls --format '{{.Name}}' | grep -E '(^backend$|_backend$)' | head -n 1)"
  if [ -z "${network_name}" ]; then
    echo "Docker network for the project was not found" >&2
    exit 1
  fi

  docker run --rm \
    --network "${network_name}" \
    -v "${backup_dir}:/backup" \
    --entrypoint mysqldump \
    schnitzler/mysqldump \
    --host db \
    --user root \
    --password="${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" > "${backup_dir}/${MYSQL_DATABASE}-${timestamp}.sql"
}

case "${1:-deploy}" in
  deploy)
    deploy_app
    ;;
  backup)
    backup_db
    ;;
  *)
    echo "Usage: $0 [deploy|backup]" >&2
    exit 1
    ;;
esac
