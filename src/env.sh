#!/usr/bin/env bash

# Environment

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
export BUILD_ROOT="$REPO_ROOT/podman-build"

export PODMAN_MACHINE_NAME="pk-machine"
export PODMAN_MACHINE_SRC_MOUNT="$REPO_ROOT"
export PODMAN_MACHINE_DST_MOUNT="$REPO_ROOT"

export PODMAN_DB_IMAGE="postgres:15.1-alpine"
export PODMAN_DB_CONTAINER="pk-db"
export PODMAN_DB_SRC_DIR="$BUILD_ROOT/mysql"
export PODMAN_DB_DST_DIR="/bitnami/mysql"
export PODMAN_DB_ROOT_PASSWORD="root"
export PODMAN_DB_DATABASE="bitnami_wordpress"
export PODMAN_DB_USER="bn_wordpress"
export PODMAN_DB_PASSWORD="wordpress"

export PODMAN_WP_IMAGE="bitnami/wordpress:latest"
export PODMAN_WP_CONTAINER="pk-wp"
export PODMAN_WP_SRC_DIR="$BUILD_ROOT/wordpress"
export PODMAN_WP_DST_DIR="/bitnami/wordpress"
export PODMAN_WP_PORT=8080
export PODMAN_WP_ADMIN_USER="admin"
export PODMAN_WP_ADMIN_PASSWORD="admin"
export PODMAN_WP_ADMIN_EMAIL="admin@localhost.com"

export PODMAN_NETWORK="presskit-live"

# Print a styled, fixed-width string
pk_print() {
  local input="$1"
  local width="$2"
  local style="$3"
  local padded ansi_reset ansi_style

  padded="$(printf '%-*.*s' "$width" "$width" "$input")"
  ansi_reset="\033[0m"

  case "$style" in
    inverted)       ansi_style="\033[7m" ;;
    red)            ansi_style="\033[31m" ;;
    green)          ansi_style="\033[32m" ;;
    blue)           ansi_style="\033[34m" ;;
    white-on-red)   ansi_style="\033[97;41m" ;;
    white-on-blue)  ansi_style="\033[97;44m" ;;
    white-on-red-bold)  ansi_style="\033[1;97;41m" ;;
    *)              ansi_style="" ;;
  esac

  echo -ne "${ansi_style}${padded}${ansi_reset}"
}

# Log a formatted line with time, label, and message
pk_log_exit() {
  local exit_code="$1"
  if [ $exit_code -ne 0 ]; then
    local label="EXIT"
    local colour="red"
  else
    local label="EXIT"
    local colour="green"
  fi
  shift;
  local message="$*"
  echo -e "$(pk_print "$(date +%H:%M:%S)" 10 white) $(pk_print "$label" 8 $colour) $(pk_print "$message" 30 white)"
  return $exit_code
}
pk_log() {
  local label="$1"
  shift
  local message="$*"
  echo -e "$(pk_print "$(date +%H:%M:%S)" 10 white) $(pk_print "$label" 8 $colour) $message"
}

pk_change_colour() {
  local colour="$1"
  echo -ne "\033[34m"
}

pk_reset_colour() {
  echo -ne "\033[0m"
}

pk_fs_cmd() {
  pk_cmd " FILES" white-on-blue "$@"
}

pk_podman() {
  pk_cmd " PODMAN" white-on-red "$@"
}

pk_cmd() {
  local label="$1"
  local colour="$2"
  shift; shift;

  # Get terminal width and calculate available width
  local term_width=$(tput cols)

  # Format the command with escaped newlines and truncate to available width
  local cmd="$*"
  local escaped_cmd="${cmd//$'\n'/\\n}" 
  local truncated_cmd="${escaped_cmd:0:60}"
  
  #[2:51:2] [INFO    ] $  [echo This is a very long line]
  echo -e "$(pk_print "$(date +%H:%M:%S)" 10 white) $(pk_print "$label" 8 $colour) $(pk_print "$truncated_cmd" 30 white)"
  
  # Execute command and format output with consistent padding
  pk_change_colour

  padding_indent=$(printf '%*s' 20 '')
  command "$@" | fmt -w "$term_width" | sed -e "s/^/$padding_indent/" -e "s/\n/\n$padding_indent/g"
  local exit_code=$?
  pk_reset_colour

  if [ $exit_code -ne 0 ]; then
    pk_log_exit $exit_code "Command exited with code $exit_code"
  else
    pk_log_exit $exit_code "Command exited with code $exit_code"
  fi

  return $exit_code
}

pk_wait_wordpress() {
  local health_level="$1"
  if [ -z "$health_level" ]; then
    health_level=1
  fi
  pk_log "STEP" "🔍 Checking WordPress ($health_level)"

  while true; do

      last_log=$(podman logs --tail 1 "${PODMAN_WP_CONTAINER}" 2>/dev/null || echo "No Logs")
      http_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ 2>/dev/null || echo "")
      if podman exec "${PODMAN_WP_CONTAINER}" wp plugin list --status=active >/dev/null 2>&1; then
          wp_cli_ok=1
      else
          wp_cli_ok=0
      fi

      pk_log "WAIT" "🔍 HTTP $http_code WP CLI $wp_cli_ok $last_log"

      if [ $health_level -eq 1 ]; then
        if [ $http_code -eq 302 ] || [ $http_code -eq 200 ]; then
          pk_log "INFO" "🥳 WordPress is ready"
          break
        fi
      fi

      if [ $health_level -eq 2 ]; then
        if [ $http_code -eq 200 ] && [ $wp_cli_ok -eq 1 ]; then
            pk_log "INFO" "🥳 WordPress is ready"
            break
        fi
      fi

      sleep 1

  done
}

pk_clean_build() {
  pk_log "STEP" "🔧 Cleaning build directory"
  pk_fs_cmd rm -rfv "$BUILD_ROOT"/*
}

pk_build_wordpress() {

  pk_log "BUILD" "Building Podman WordPress environment"
  pk_log "" "📁 Local build and persistence directories"
  pk_log "" "🎯 Build Root: $BUILD_ROOT"
  pk_log "" "🎯 WordPress: $PODMAN_WP_SRC_DIR"
  pk_log "" "🎯 Database: $PODMAN_DB_SRC_DIR"
  pk_log "VM" "🤖 Podman Machine: $PODMAN_MACHINE_NAME"
  pk_log "" "📁 $PODMAN_MACHINE_DST_MOUNT"
  pk_log "PODMAN" "🛜  Network: $PODMAN_NETWORK"
  pk_log "" "🥡 Database: $PODMAN_DB_CONTAINER"
  pk_log "" "🥡 WordPress: $PODMAN_WP_CONTAINER"

  pk_log "STEP" "🔧 Creating build directory"
  pk_fs_cmd mkdir -vp "$BUILD_ROOT"

  pk_log "STEP" "🔧 Creating WordPress source directory"
  pk_fs_cmd mkdir -vp "$PODMAN_WP_SRC_DIR"

  pk_log "STEP" "🔧 Creating Database source directory"
  pk_fs_cmd mkdir -vp "$PODMAN_DB_SRC_DIR"

  pk_log "STEP" "🔧 Checking Podman machine"
  if podman machine list --format '{{.Name}}' | grep -q "$PODMAN_MACHINE_NAME"; then
    pk_log "INFO" "🥳 Podman machine is ready"
  else
    pk_log "" "🔧 Podman machine does not exist, creating machine '$PODMAN_MACHINE_NAME'"
    pk_log "" "📁 $PODMAN_MACHINE_SRC_MOUNT:$PODMAN_MACHINE_DST_MOUNT"
    podman machine init --rootful --volume "$PODMAN_MACHINE_SRC_MOUNT:$PODMAN_MACHINE_DST_MOUNT"
    podman machine start
  fi


  pk_log "STEP" "🌐 Checking network '$PODMAN_NETWORK'"
  if podman network list --format '{{.Name}}' | grep -q "$PODMAN_NETWORK"; then
    pk_log "INFO" "🥳 Network is ready"
  else
    pk_log "" "🔧 Network does not exist, creating network '$PODMAN_NETWORK'"
    podman network create "$PODMAN_NETWORK"
  fi

  pk_log "INFO" "🔧 Creating Database container '$PODMAN_DB_CONTAINER'"
  pk_log "" "📁 $PODMAN_DB_SRC_DIR:$PODMAN_DB_DST_DIR"
  podman run -d --name "$PODMAN_DB_CONTAINER" --network "$PODMAN_NETWORK" \
      -e MARIADB_ROOT_PASSWORD="$PODMAN_DB_PASSWORD" \
      -e MARIADB_DATABASE="$PODMAN_DB_DATABASE" \
      -e MARIADB_USER="$PODMAN_DB_USER" \
      -e MARIADB_PASSWORD="$PODMAN_DB_PASSWORD" \
      -v "$PODMAN_DB_SRC_DIR:$PODMAN_DB_DST_DIR" \
      --replace \
      bitnami/mariadb:latest >/dev/null

  pk_log "INFO" "🔧 Creating WordPress container '$PODMAN_WP_CONTAINER'"
  pk_log "" "📁 $PODMAN_WP_SRC_DIR:$PODMAN_WP_DST_DIR"
  podman run -d --name "$PODMAN_WP_CONTAINER" --network "$PODMAN_NETWORK" \
    -v "$PODMAN_WP_SRC_DIR:$PODMAN_WP_DST_DIR" \
    -p "$PODMAN_WP_PORT:8080" \
    -e WORDPRESS_DATABASE_HOST="$PODMAN_DB_CONTAINER" \
    -e WORDPRESS_DATABASE_PORT_NUMBER=3306 \
    -e WORDPRESS_DATABASE_NAME="$PODMAN_DB_DATABASE" \
    -e WORDPRESS_DATABASE_USER="$PODMAN_DB_USER" \
    -e WORDPRESS_DATABASE_PASSWORD="$PODMAN_DB_PASSWORD" \
    -e WORDPRESS_USERNAME="$PODMAN_WP_ADMIN_USER" \
    -e WORDPRESS_PASSWORD="$PODMAN_WP_ADMIN_PASSWORD" \
    -e WORDPRESS_EMAIL="$PODMAN_WP_ADMIN_EMAIL" \
    --replace \
    bitnami/wordpress:latest >/dev/null

}

pk_activate_core() {
  pk_log "STEP" "🔧 Activating Core"
  pk_podman podman exec -it "$PODMAN_WP_CONTAINER" wp plugin activate presskit-core
  podman logs --tail 1 -f "$PODMAN_WP_CONTAINER"
}

pk_install_core() {

  local core_src="$( cd $REPO_ROOT/../core && pwd )"
  local core_dst="$PODMAN_WP_SRC_DIR/wp-content/plugins/presskit-core" 

  if [ ! -d "$core_src" ]; then
    pk_log "ERROR" "Core source directory does not exist"
    return 1
  fi

  pk_log "STEP" "🔧 Installing Core"
  pk_log "" "📁 $core_src:$core_dst"
  rsync -avz --delete "$core_src/" "$core_dst/"

  pk_log "STEP" "🔧 Installing Core Dependencies"
  pk_log "CMD" "cd $core_dst && composer install"
  cd "$core_dst" && composer install
}

pk_install_core_ui() {

  local core_ui_src="$( cd $REPO_ROOT/../core-ui/ && pwd )"
  local core_ui_dist="$( cd $REPO_ROOT/../core-ui/dist/ && pwd )"
  local core_ui_dst="$PODMAN_WP_SRC_DIR/wp-content/plugins/presskit-core/ui"

  if [ ! -d "$core_ui_src" ]; then
    pk_log "ERROR" "Core UI source directory does not exist"
    return 1
  fi

  pk_log "STEP" "🔧 Building Core UI"
  pk_log "CMD" "cd $core_ui_src/.. && npm run build"
  cd "$core_ui_src" && npm run build

  pk_log "STEP" "🔧 Installing Core UI"
  pk_log "CMD" "rsync -avz --delete $core_ui_dist/ $core_ui_dst/"
  rsync -avz --delete "$core_ui_dist/" "$core_ui_dst/"

  ls -l "$core_ui_dst"

}