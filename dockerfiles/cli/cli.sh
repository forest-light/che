#!/bin/bash
# Copyright (c) 2012-2016 Codenvy, S.A.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
#   Tyler Jewell - Initial Implementation
#


cli_init() {
#  GLOBAL_NAME_MAP=$(docker info | grep "Name:" | cut -d" " -f2)
#  GLOBAL_HOST_ARCH=$(docker version --format {{.Client}} | cut -d" " -f5)
#  GLOBAL_HOST_IP=$(docker run --net host --rm eclipse/che-ip:nightly)
#  GLOBAL_UNAME=$(docker run --rm alpine sh -c "uname -r")
#  GLOBAL_GET_DOCKER_HOST_IP=$(get_docker_host_ip)

  grab_offline_images
  grab_initial_images
  check_host_volume_mount

  DEFAULT_CHE_CLI_ACTION="help"
  CHE_CLI_ACTION=${CHE_CLI_ACTION:-${DEFAULT_CHE_CLI_ACTION}}

  # This is the IP address that Che is binding itself to.
  init_host_ip
  DEFAULT_CHE_HOST=$GLOBAL_HOST_IP
  CHE_HOST=${CHE_HOST:-${DEFAULT_CHE_HOST}}
  DEFAULT_CHE_PORT=8080
  CHE_PORT=${CHE_PORT:-${DEFAULT_CHE_PORT}}


  if [[ "${CHE_HOST}" = "" ]]; then
      info "Welcome to Eclipse Che!"
      info ""
      info "We did not auto-detect a valid HOST or IP address."
      info "Pass CHE_HOST with your hostname or IP address."
      info ""
      info "Rerun the CLI:"
      info "  docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock"
      info "                      -v <local-path>:/che"
      info "                      -e CHE_HOST=<your-ip-or-host>"
      info "                         eclipse/che-cli:${CHE_VERSION} $@"
      return 2;
  fi


  CHE_VERSION_FILE="che.ver"
  CHE_ENVIRONMENT_FILE="che.env"
  CHE_COMPOSE_FILE="docker-compose-container.yml"
  CHE_SERVER_CONTAINER_NAME="che"
  CHE_CONFIG_BACKUP_FILE_NAME="che_config_backup.tar"
  CHE_INSTANCE_BACKUP_FILE_NAME="che_instance_backup.tar"
  DOCKER_CONTAINER_NAME_PREFIX="che_"

  REFERENCE_HOST_ENVIRONMENT_FILE="${CHE_HOST_CONFIG}/${CHE_ENVIRONMENT_FILE}"
  REFERENCE_HOST_COMPOSE_FILE="${CHE_HOST_INSTANCE}/${CHE_COMPOSE_FILE}"
  REFERENCE_CONTAINER_ENVIRONMENT_FILE="${CHE_CONTAINER_CONFIG}/${CHE_ENVIRONMENT_FILE}"
  REFERENCE_CONTAINER_COMPOSE_FILE="${CHE_CONTAINER_INSTANCE}/${CHE_COMPOSE_FILE}"

  CHE_MANIFEST_DIR="/version"
  CHE_OFFLINE_FOLDER="/che/backup"

  CHE_HOST_CONFIG_MANIFESTS_FOLDER="$CHE_HOST_CONFIG/manifests"
  CHE_CONTAINER_CONFIG_MANIFESTS_FOLDER="$CHE_CONTAINER_CONFIG/manifests"

  CHE_HOST_CONFIG_MODULES_FOLDER="$CHE_HOST_CONFIG/modules"
  CHE_CONTAINER_CONFIG_MODULES_FOLDER="$CHE_CONTAINER_CONFIG/modules"

  # TODO: Change this to use the current folder or perhaps ~?
  if is_boot2docker && has_docker_for_windows_client; then
    if [[ "${CHE_HOST_INSTANCE,,}" != *"${USERPROFILE,,}"* ]]; then
      CHE_HOST_INSTANCE=$(get_mount_path "${USERPROFILE}/.${CHE_MINI_PRODUCT_NAME}/")
      warning "Boot2docker for Windows - CHE_INSTANCE set to $CHE_HOST_INSTANCE"
    fi
    if [[ "${CHE_HOST_CONFIG,,}" != *"${USERPROFILE,,}"* ]]; then
      CHE_HOST_CONFIG=$(get_mount_path "${USERPROFILE}/.${CHE_MINI_PRODUCT_NAME}/")
      warning "Boot2docker for Windows - CHE_CONFIG set to $CHE_HOST_CONFIG"
    fi
  fi
}

grab_offline_images(){
  # If you are using eclipse che in offline mode, images must be loaded here
  # This is the point where we know that docker is working, but before we run any utilities
  # that require docker.
  if [ ! -z ${2+x} ]; then
    if [ "${2}" == "--offline" ]; then
      info "init" "Importing ${CHE_MINI_PRODUCT_NAME} Docker images from tars..."

      if [ ! -d offline ]; then
        info "init" "You requested offline loading of images, but could not find 'offline/'"
        return 2;
      fi

      IFS=$'\n'
      for file in "offline"/*.tar
      do
        if ! $(docker load < "offline"/"${file##*/}" > /dev/null); then
          error "Failed to restore ${CHE_MINI_PRODUCT_NAME} Docker images"
          return 2;
        fi
        info "init" "Loading ${file##*/}..."
      done
    fi
  fi
}

grab_initial_images() {
  # Prep script by getting default image
  if [ "$(docker images -q alpine:3.4 2> /dev/null)" = "" ]; then
    info "cli" "Pulling image alpine:3.4"
    log "docker pull alpine:3.4 >> \"${LOGS}\" 2>&1"
    TEST=""
    docker pull alpine:3.4 >> "${LOGS}" 2>&1 || TEST=$?
    if [ "$TEST" = "1" ]; then
      error "Image alpine:3.4 unavailable. Not on dockerhub or built locally."
      return 1;
    fi
  fi

  if [ "$(docker images -q appropriate/curl 2> /dev/null)" = "" ]; then
    info "cli" "Pulling image appropriate/curl:latest"
    log "docker pull appropriate/curl:latest >> \"${LOGS}\" 2>&1"
    TEST=""
    docker pull appropriate/curl >> "${LOGS}" 2>&1 || TEST=$?
    if [ "$TEST" = "1" ]; then
      error "Image appropriate/curl:latest unavailable. Not on dockerhub or built locally."
      return 1;
    fi
  fi

  if [ "$(docker images -q eclipse/che-ip:nightly 2> /dev/null)" = "" ]; then
    info "cli" "Pulling image eclipse/che-ip:nightly"
    log "docker pull eclipse/che-ip:nightly >> \"${LOGS}\" 2>&1"
    TEST=""
    docker pull eclipse/che-ip:nightly >> "${LOGS}" 2>&1 || TEST=$?
    if [ "$TEST" = "1" ]; then
      error "Image eclipse/che-ip:nightly unavailable. Not on dockerhub or built locally."
      return 1;
    fi
  fi

#  if [ "$(docker images -q docker/compose:1.8.1 2> /dev/null)" = "" ]; then
#    info "cli" "Pulling image docker/compose:1.8.1"
#    log "docker pull docker/compose:1.8.1 >> \"${LOGS}\" 2>&1"
#    TEST=""
#    docker pull docker/compose:1.8.1 >> "${LOGS}" 2>&1 || TEST=$?
#    if [ "$TEST" = "1" ]; then
#      error "Image docker/compose:1.8.1 not found on dockerhub or locally."
#      return 1;
#    fi
#  fi
}

check_host_volume_mount() {
  echo 'test' > /che/test  > "${LOGS}" 2>&1

  if [[ ! -f /che/test ]]; then
    error "Docker installed, but unable to write files to your host."
    error "Have you enabled Docker to allow mounting host directories?"
    error "Did our CLI not have user rights to create files on your host?"
    return 2;
  fi

  rm -rf /che/test
}



cli_parse () {
  debug $FUNCNAME
  if [ $# -eq 0 ]; then
    CHE_CLI_ACTION="help"
  else
    case $1 in
      version|init|config|start|stop|restart|destroy|rmi|config|download|offline|info|network|debug|help|-h|--help)
        CHE_CLI_ACTION=$1
      ;;
      *)
        # unknown option
        error "You passed an unknown command line option."
        return 1;
      ;;
    esac
  fi
}

cli_cli() {
  case ${CHE_CLI_ACTION} in
    download)
      shift
      cmd_download "$@"
    ;;
    init)
      shift
      cmd_init "$@"
    ;;
    config)
      shift
      cmd_config "$@"
    ;;
    start)
      shift
      cmd_start "$@"
    ;;
    stop)
      shift
      cmd_stop "$@"
    ;;
    restart)
      shift
      cmd_restart "$@"
    ;;
    destroy)
      shift
      cmd_destroy "$@"
    ;;
    rmi)
      shift
      cmd_rmi "$@"
    ;;
    version)
      shift
      cmd_version "$@"
    ;;
    offline)
      shift
      cmd_offline
    ;;
    info)
      shift
      cmd_info "$@"
    ;;
    debug)
      shift
      cmd_debug "$@"
    ;;
    network)
      shift
      cmd_network "$@"
    ;;
    help)
      usage
    ;;
  esac
}

get_mount_path() {
  debug $FUNCNAME
  FULL_PATH=$(get_full_path "${1}")
  POSIX_PATH=$(convert_windows_to_posix "${FULL_PATH}")
  CLEAN_PATH=$(get_clean_path "${POSIX_PATH}")
  echo $CLEAN_PATH
}

get_full_path() {
  debug $FUNCNAME
  # create full directory path
  echo "$(cd "$(dirname "${1}")"; pwd)/$(basename "$1")"
}

convert_windows_to_posix() {
  debug $FUNCNAME
  echo "/"$(echo "$1" | sed 's/\\/\//g' | sed 's/://')
}

convert_posix_to_windows() {
  debug $FUNCNAME
  # Remove leading slash
  VALUE="${1:1}"

  # Get first character (drive letter)
  VALUE2="${VALUE:0:1}"

  # Replace / with \
  VALUE3=$(echo ${VALUE} | tr '/' '\\' | sed 's/\\/\\\\/g')

  # Replace c\ with c:\ for drive letter
  echo "$VALUE3" | sed "s/./$VALUE2:/1"
}

get_clean_path() {
  debug $FUNCNAME
  INPUT_PATH=$1
  # \some\path => /some/path
  OUTPUT_PATH=$(echo ${INPUT_PATH} | tr '\\' '/')
  # /somepath/ => /somepath
  OUTPUT_PATH=${OUTPUT_PATH%/}
  # /some//path => /some/path
  OUTPUT_PATH=$(echo ${OUTPUT_PATH} | tr -s '/')
  # "/some/path" => /some/path
  OUTPUT_PATH=${OUTPUT_PATH//\"}
  echo ${OUTPUT_PATH}
}

get_docker_host_ip() {
  debug $FUNCNAME
  echo $GLOBAL_HOST_IP
}

get_docker_install_type() {
  debug $FUNCNAME
  if is_boot2docker; then
    echo "boot2docker"
  elif is_docker_for_windows; then
    echo "docker4windows"
  elif is_docker_for_mac; then
    echo "docker4mac"
  else
    echo "native"
  fi
}


has_docker_for_windows_client(){
  debug $FUNCNAME
  if [[ $(get_docker_host_ip) = "10.0.75.2" ]]; then
    return 0
  else
    return 1
  fi
}

is_boot2docker() {
  debug $FUNCNAME
  if uname -r | grep -q 'boot2docker'; then
    return 0
  else
    return 1
  fi
}

is_docker_for_windows() {
  debug $FUNCNAME
  if uname -r | grep -q 'moby' && has_docker_for_windows_client; then
    return 0
  else
    return 1
  fi
}

is_docker_for_mac() {
  debug $FUNCNAME
  if uname -r | grep -q 'moby' && ! has_docker_for_windows_client; then
    return 0
  else
    return 1
  fi
}

is_native() {
  debug $FUNCNAME
  if [ $(get_docker_install_type) = "native" ]; then
    return 0
  else
    return 1
  fi
}

has_env_variables() {
  debug $FUNCNAME
  PROPERTIES=$(env | grep CHE_)

  if [ "$PROPERTIES" = "" ]; then
    return 1
  else
    return 0
  fi
}

update_image_if_not_found() {
  debug $FUNCNAME

  text "${GREEN}INFO:${NC} (${CHE_MINI_PRODUCT_NAME} download): Checking for image '$1'..."
  CURRENT_IMAGE=$(docker images -q "$1")
  if [ "${CURRENT_IMAGE}" == "" ]; then
    text "not found\n"
    update_image $1
  else
    text "found\n"
  fi
}

update_image() {
  debug $FUNCNAME

  if [ "${1}" == "--force" ]; then
    shift
    info "download" "Removing image $1"
    log "docker rmi -f $1 >> \"${LOGS}\""
    docker rmi -f $1 >> "${LOGS}" 2>&1 || true
  fi

  if [ "${1}" == "--pull" ]; then
    shift
  fi

  info "download" "Pulling image $1"
  text "\n"
  log "docker pull $1 >> \"${LOGS}\" 2>&1"
  TEST=""
  docker pull $1 || TEST=$?
  if [ "$TEST" = "1" ]; then
    error "Image $1 unavailable. Not on dockerhub or built locally."
    return 2;
  fi
  text "\n"
}

port_open(){

#  log "netstat -an | grep 0.0.0.0:$1 >> \"${LOGS}\" 2>&1"
#  netstat -an | grep 0.0.0.0:$1 >> "${LOGS}" 2>&1
#  docker run --rm --net host alpine netstat -an | grep ${CHE_HOST}:$1 >> "${LOGS}" 2>&1

  docker run -d -p $1:$1 --name fake alpine:3.4 httpd -f -p $1 -h /etc/ > /dev/null 2>&1
  NETSTAT_EXIT=$?
  docker rm -f fake > /dev/null 2>&1

  if [ $NETSTAT_EXIT = 125 ]; then
    return 1
  else
    return 0
  fi
}

container_exist_by_name(){
  docker inspect ${1} > /dev/null 2>&1
  if [ "$?" == "0" ]; then
    return 0
  else
    return 1
  fi
}

get_server_container_id() {
  log "docker inspect -f '{{.Id}}' ${1}"
  docker inspect -f '{{.Id}}' ${1}
}

wait_until_container_is_running() {
  CONTAINER_START_TIMEOUT=${1}

  ELAPSED=0
  until container_is_running ${2} || [ ${ELAPSED} -eq "${CONTAINER_START_TIMEOUT}" ]; do
    log "sleep 1"
    sleep 1
    ELAPSED=$((ELAPSED+1))
  done
}

container_is_running() {
  if [ "$(docker ps -qa -f "status=running" -f "id=${1}" | wc -l)" -eq 0 ]; then
    return 1
  else
    return 0
  fi
}

wait_until_server_is_booted () {
  SERVER_BOOT_TIMEOUT=${1}

  ELAPSED=0
  until server_is_booted ${2} || [ ${ELAPSED} -eq "${SERVER_BOOT_TIMEOUT}" ]; do
    log "sleep 2"
    sleep 2
    # Total hack - having to restart haproxy for some reason on windows
    ELAPSED=$((ELAPSED+1))
  done
}

server_is_booted() {
  HTTP_STATUS_CODE=$(curl -I -k $CHE_HOST:$CHE_PORT/api/ \
                     -s -o "${LOGS}" --write-out "%{http_code}")
  if [[ "${HTTP_STATUS_CODE}" = "200" ]] || [[ "${HTTP_STATUS_CODE}" = "302" ]]; then
    return 0
  else
    return 1
  fi
}


check_if_booted() {
  CURRENT_CHE_SERVER_CONTAINER_ID=$(get_server_container_id $CHE_SERVER_CONTAINER_NAME)
  wait_until_container_is_running 20 ${CURRENT_CHE_SERVER_CONTAINER_ID}
  if ! container_is_running ${CURRENT_CHE_SERVER_CONTAINER_ID}; then
    error "(${CHE_MINI_PRODUCT_NAME} start): Timeout waiting for ${CHE_MINI_PRODUCT_NAME} container to start."
    return 1
  fi

  info "start" "Server logs at \"docker logs -f ${CHE_SERVER_CONTAINER_NAME}\""
  info "start" "Server booting..."
  wait_until_server_is_booted 60 ${CURRENT_CHE_SERVER_CONTAINER_ID}

  if server_is_booted ${CURRENT_CHE_SERVER_CONTAINER_ID}; then
    info "start" "Booted and reachable"
    info "start" "Ver: $(get_installed_version)"
    if ! is_docker_for_mac; then
      info "start" "Use: http://${CHE_HOST}:${CHE_PORT}"
      info "start" "API: http://${CODENVY_HOST}:${CHE_PORT}/swagger"
    else
      info "start" "Use: http://localhost:${CHE_PORT}"
      info "start" "API: http://localhost:${CHE_PORT}/swagger"
    fi
  else
    error "(${CHE_MINI_PRODUCT_NAME} start): Timeout waiting for server. Run \"docker logs ${CHE_SERVER_CONTAINER_NAME}\" to inspect the issue."
    return 1
  fi
}

is_initialized() {
  if [[ -d "${CHE_CONTAINER_CONFIG_MANIFESTS_FOLDER}" ]] && \
     [[ -d "${CHE_CONTAINER_CONFIG_MODULES_FOLDER}" ]] && \
     [[ -f "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}" ]] && \
     [[ -f "${CHE_CONTAINER_CONFIG}/${CHE_VERSION_FILE}" ]]; then
    return 0
  else
    return 1
  fi
}

has_version_registry() {
  if [ -d /version/$1 ]; then
    return 0;
  else
    return 1;
  fi
}

list_versions(){
  # List all subdirectories and then print only the file name
  for version in /version/* ; do
    text " ${version##*/}\n"
  done
}

version_error(){
  text "\nWe could not find version '$1'. Available versions:\n"
  list_versions
  text "\nSet CHE_VERSION=<version> and rerun.\n\n"
}

### Returns the list of Eclipse Che images for a particular version of Eclipse Che
### Sets the images as environment variables after loading from file
get_image_manifest() {
  info "cli" "Checking registry for version '$1' images"
  if ! has_version_registry $1; then
    version_error $1
    return 1;
  fi

  IMAGE_LIST=$(cat /version/$1/images)
  IFS=$'\n'
  for SINGLE_IMAGE in $IMAGE_LIST; do
    log "eval $SINGLE_IMAGE"
    eval $SINGLE_IMAGE
  done
}


can_upgrade() {
  #  4.7.2 -> 5.0.0-M2-SNAPSHOT  <insert-syntax>
  #  4.7.2 -> 4.7.3              <insert-syntax>
  while IFS='' read -r line || [[ -n "$line" ]]; do
    VER=$(echo $line | cut -d ' ' -f1)
    UPG=$(echo $line | cut -d ' ' -f2)

    # Loop through and find all matching versions
    if [[ "${VER}" == "${1}" ]]; then
      if [[ "${UPG}" == "${2}" ]]; then
        return 0
      fi
    fi
  done < "$CHE_MANIFEST_DIR"/upgrades

  return 1
}


print_upgrade_manifest() {
  #  4.7.2 -> 5.0.0-M2-SNAPSHOT  <insert-syntax>
  #  4.7.2 -> 4.7.3              <insert-syntax>
  while IFS='' read -r line || [[ -n "$line" ]]; do
    VER=$(echo $line | cut -d ' ' -f1)
    UPG=$(echo $line | cut -d ' ' -f2)
    text "  "
    text "%s" $VER
    for i in `seq 1 $((25-${#VER}))`; do text " "; done
    text "%s" $UPG
    text "\n"
  done < "$CHEY_MANIFEST_DIR"/upgrades
}

print_version_manifest() {
  while IFS='' read -r line || [[ -n "$line" ]]; do
    VER=$(echo $line | cut -d ' ' -f1)
    CHA=$(echo $line | cut -d ' ' -f2)
    UPG=$(echo $line | cut -d ' ' -f3)
    text "  "
    text "%s" $VER
    for i in `seq 1 $((25-${#VER}))`; do text " "; done
    text "%s" $CHA
    for i in `seq 1 $((18-${#CHA}))`; do text " "; done
    text "%s" $UPG
    text "\n"
  done < "$CHE_MANIFEST_DIR"/versions
}

get_installed_version() {
  if ! is_initialized; then
    echo "<not-installed>"
  else
    cat "${CHE_CONTAINER_CONFIG}"/$CHE_VERSION_FILE
  fi
}

get_installed_installdate() {
  if ! is_initialized; then
    echo "<not-installed>"
  else
    cat "${CHE_CONFIG}"/$CHE_VERSION_FILE
  fi
}

# Usage:
#   confirm_operation <Warning message> [--force|--no-force]
confirm_operation() {
  debug $FUNCNAME

  FORCE_OPERATION=${2:-"--no-force"}

  if [ ! "${FORCE_OPERATION}" == "--quiet" ]; then
    # Warn user with passed message
    info "${1}"
    text "\n"
    read -p "      Are you sure? [N/y] " -n 1 -r
    text "\n\n"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      return 1;
    else
      return 0;
    fi
  fi
}

# Runs puppet image to generate Eclipse Che configuration
generate_configuration_with_puppet() {
  debug $FUNCNAME

  if is_docker_for_windows; then
      CHE_ENV_FILE=$(convert_posix_to_windows "${CHE_HOST_INSTANCE}/config/$CHE_MINI_PRODUCT_NAME.env")
    else
      CHE_ENV_FILE="${CHE_HOST_INSTANCE}/config/$CHE_MINI_PRODUCT_NAME.env"
    fi

  # Note - bug in docker requires relative path for env, not absolute
  log "docker_run -it --env-file=\"${REFERENCE_CONTAINER_ENVIRONMENT_FILE}\" \
                      --env-file=/version/$CHE_VERSION/images \
                  -v \"${CHE_HOST_INSTANCE}\":/opt/${CHE_MINI_PRODUCT_NAME}:rw \
                  -v \"${CHE_HOST_CONFIG_MANIFESTS_FOLDER}\":/etc/puppet/manifests:ro \
                  -v \"${CHE_HOST_CONFIG_MODULES_FOLDER}\":/etc/puppet/modules:ro \
                  -e "CHE_ENV_FILE=${CHE_ENV_FILE}" \
                      $IMAGE_PUPPET \
                          apply --modulepath \
                                /etc/puppet/modules/ \
                                /etc/puppet/manifests/${CHE_MINI_PRODUCT_NAME}.pp --show_diff \"$@\""
  docker_run -it  --env-file="${REFERENCE_CONTAINER_ENVIRONMENT_FILE}" \
                  --env-file=/version/$CHE_VERSION/images \
                  -v "${CHE_HOST_INSTANCE}":/opt/${CHE_MINI_PRODUCT_NAME}:rw \
                  -v "${CHE_HOST_CONFIG_MANIFESTS_FOLDER}":/etc/puppet/manifests:ro \
                  -v "${CHE_HOST_CONFIG_MODULES_FOLDER}":/etc/puppet/modules:ro \
                  -e "CHE_ENV_FILE=${CHE_ENV_FILE}" \
                      $IMAGE_PUPPET \
                          apply --modulepath \
                                /etc/puppet/modules/ \
                                /etc/puppet/manifests/${CHE_MINI_PRODUCT_NAME}.pp --show_diff "$@"
}

# return date in format which can be used as a unique file or dir name
# example 2016-10-31-1477931458
get_current_date() {
    date +'%Y-%m-%d-%s'
}

###########################################################################
### END HELPER FUNCTIONS
###
### START CLI COMMANDS
###########################################################################
cmd_download() {
  debug "$FUNCNAME and che version is $CHE_VERSION"

  FORCE_UPDATE=${1:-"--no-force"}

  get_image_manifest $CHE_VERSION

  IFS=$'\n'
  for SINGLE_IMAGE in $IMAGE_LIST; do
    VALUE_IMAGE=$(echo $SINGLE_IMAGE | cut -d'=' -f2)
    if [[ $FORCE_UPDATE == "--force" ]] ||
       [[ $FORCE_UPDATE == "--pull" ]]; then
      update_image $FORCE_UPDATE $VALUE_IMAGE
    else
      update_image_if_not_found $VALUE_IMAGE
    fi
  done
}

cmd_init() {
  debug $FUNCNAME

  FORCE_UPDATE=${1:-"--no-force"}
  if [ "${FORCE_UPDATE}" == "--no-force" ]; then
    # If che.environment file exists, then fail
    if is_initialized; then
      info "init" "Already initialized."
      return 1
    fi
  fi

  cmd_download $FORCE_UPDATE

  if [ -z ${IMAGE_INIT+x} ]; then
    get_image_manifest $CHE_VERSION
  fi



  info "init" "Installing configuration and bootstrap variables:"
  log "mkdir -p \"${CHE_CONTAINER_CONFIG}\""
  mkdir -p "${CHE_CONTAINER_CONFIG}"
  log "mkdir -p \"${CHE_CONTAINER_INSTANCE}\""
  mkdir -p "${CHE_CONTAINER_INSTANCE}"

  if [ ! -w "${CHE_CONTAINER_CONFIG}" ]; then
    error "CHE_CONTAINER_CONFIG is not writable. Aborting."
    return 1;
  fi

  if [ ! -w "${CHE_CONTAINER_INSTANCE}" ]; then
    error "CHE_CONTAINER_INSTANCE is not writable. Aborting."
    return 1;
  fi

  # in development mode we use init files from repo otherwise we use it from docker image
  if [ "${CHE_DEVELOPMENT_MODE}" = "on" ]; then
    docker_run -v "${CHE_HOST_CONFIG}":/copy \
               -v "${CHE_HOST_DEVELOPMENT_REPO}":/files \
                   $IMAGE_INIT
  else
    docker_run -v "${CHE_HOST_CONFIG}":/copy $IMAGE_INIT
  fi
  # After initialization, add che.env with self-discovery.
  sed -i'.bak' "s|#CHE_HOST=.*|CHE_HOST=${CHE_HOST}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
  info "init" "  CHE_HOST=${CHE_HOST}"
  sed -i'.bak' "s|#CHE_PORT=.*|CHE_PORT=${CHE_PORT}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
  info "init" "  CHE_PORT=${CHE_PORT}"
  sed -i'.bak' "s|#CHE_VERSION=.*|CHE_VERSION=${CHE_VERSION}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
  info "init" "  CHE_VERSION=${CHE_VERSION}"
  sed -i'.bak' "s|#CHE_CONFIG=.*|CHE_CONFIG=${CHE_HOST_CONFIG}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
  info "init" "  CHE_CONFIG=${CHE_HOST_CONFIG}"
  sed -i'.bak' "s|#CHE_INSTANCE=.*|CHE_INSTANCE=${CHE_HOST_INSTANCE}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
  info "init" "  CHE_INSTANCE=${CHE_HOST_INSTANCE}"

  if [ "${CHE_DEVELOPMENT_MODE}" == "on" ]; then
    sed -i'.bak' "s|#CHE_ENVIRONMENT=.*|CHE_ENVIRONMENT=development|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
    info "init" "  CHE_ENVIRONMENT=development"
    sed -i'.bak' "s|#CHE_DEVELOPMENT_REPO=.*|CHE_DEVELOPMENT_REPO=${CHE_HOST_DEVELOPMENT_REPO}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
    info "init" "  CHE_DEVELOPMENT_REPO=${CHE_HOST_DEVELOPMENT_REPO}"
    sed -i'.bak' "s|#CHE_DEVELOPMENT_TOMCAT=.*|CHE_DEVELOPMENT_TOMCAT=${CHE_DEVELOPMENT_TOMCAT}|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
    info "init" "  CHE_DEVELOPMENT_TOMCAT=${CHE_DEVELOPMENT_TOMCAT}"
  else
    sed -i'.bak' "s|#CHE_ENVIRONMENT=.*|CHE_ENVIRONMENT=production|" "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}"
    info "init" "  CHE_ENVIRONMENT=production"
  fi

  rm -rf "${REFERENCE_CONTAINER_ENVIRONMENT_FILE}".bak > /dev/null 2>&1

  # Write the Che version to che.ver
  echo "$CHE_VERSION" > "${CHE_CONTAINER_CONFIG}/${CHE_VERSION_FILE}"
}

cmd_config() {
  debug $FUNCNAME

  # If the system is not initialized, initalize it.
  # If the system is already initialized, but a user wants to update images, then re-download.
  FORCE_UPDATE=${1:-"--no-force"}
  if ! is_initialized; then
    cmd_init $FORCE_UPDATE
  elif [[ "${FORCE_UPDATE}" == "--pull" ]] || \
       [[ "${FORCE_UPDATE}" == "--force" ]]; then
    cmd_download $FORCE_UPDATE
  fi

  # If the CHE_VERSION set by an environment variable does not match the value of
  # the che.ver file of the installed instance, then do not proceed as there is a
  # confusion between what the user has set and what the instance expects.
  INSTALLED_VERSION=$(get_installed_version)
  if [[ $CHE_VERSION != $INSTALLED_VERSION ]]; then
    info "config" "CHE_VERSION=$CHE_VERSION does not match ${CHE_ENVIRONMENT_FILE}=$INSTALLED_VERSION. Aborting."
    info "config" "This happens if the <version> of your Docker image is different from ${CHE_HOST_CONFIG}/${CHE_ENVIRONMENT_FILE}"
    return 1
  fi

  if [ -z ${IMAGE_PUPPET+x} ]; then
    get_image_manifest $CHE_VERSION
  fi

  # Development mode
  if [ "${CHE_DEVELOPMENT_MODE}" = "on" ]; then
    # if dev mode is on, pick configuration sources from repo.
    # please note that in production mode update of configuration sources must be only on update.
    docker_run -v "${CHE_HOST_CONFIG}":/copy \
               -v "${CHE_HOST_DEVELOPMENT_REPO}":/files \
                  $IMAGE_INIT

    # in development mode to avoid permissions issues we copy tomcat assembly to ${CHE_INSTANCE}
    # if eclipse che development tomcat exist we remove it
    if [[ -d "${CHE_CONTAINER_INSTANCE}/dev" ]]; then
        log "docker_run -v \"${CHE_HOST_INSTANCE}/dev\":/root/dev alpine:3.4 sh -c \"rm -rf /root/dev/*\""
        docker_run -v "${CHE_HOST_INSTANCE}/dev":/root/dev alpine:3.4 sh -c "rm -rf /root/dev/*"
        log "rm -rf \"${CHE_HOST_INSTANCE}/dev\" >> \"${LOGS}\""
        rm -rf "${CHE_CONTAINER_INSTANCE}/dev"
    fi
    # copy eclipse che development tomcat to ${CHE_INSTANCE} folder
    cp -r "$(get_mount_path $(echo $CHE_CONTAINER_DEVELOPMENT_REPO/$DEFAULT_CHE_DEVELOPMENT_TOMCAT-*/))" \
        "${CHE_CONTAINER_INSTANCE}/dev"
  fi

  info "config" "Generating $CHE_MINI_PRODUCT_NAME configuration..."
  # Run the docker configurator
  if [ "${CHE_DEVELOPMENT_MODE}" = "on" ]; then
    # generate configs and print puppet output logs to console if dev mode is on
    generate_configuration_with_puppet
  else
    generate_configuration_with_puppet >> "${LOGS}"
  fi

}

cmd_start() {
  debug $FUNCNAME

  # If Eclipse Che is already started or booted, then terminate early.
  if container_exist_by_name $CHE_SERVER_CONTAINER_NAME; then
    CURRENT_CHE_SERVER_CONTAINER_ID=$(get_server_container_id $CHE_SERVER_CONTAINER_NAME)
    if container_is_running ${CURRENT_CHE_SERVER_CONTAINER_ID} && \
       server_is_booted ${CURRENT_CHE_SERVER_CONTAINER_ID}; then
       info "start" "$CHE_MINI_PRODUCT_NAME is already running"
       info "start" "Server logs at \"docker logs -f ${CHE_SERVER_CONTAINER_NAME}\""
       info "start" "Ver: $(get_installed_version)"
       if ! is_docker_for_mac; then
         info "start" "Use: http://${CHE_HOST}"
         info "start" "API: http://${CHE_HOST}/swagger"
       else
         info "start" "Use: http://localhost"
         info "start" "API: http://localhost/swagger"
       fi
       return
    fi
  fi
  # To protect users from accidentally updating their Eclipse Che servers when they didn't mean
  # to, which can happen if CHE_VERSION=latest
  FORCE_UPDATE=${1:-"--no-force"}
  # Always regenerate puppet configuration from environment variable source, whether changed or not.
  # If the current directory is not configured with an .env file, it will initialize
  cmd_config $FORCE_UPDATE

  # Begin tests of open ports that we require
  info "start" "Preflight checks"
  text   "         port $CHE_PORT (http):       $(port_open $CHE_PORT && echo "${GREEN}[AVAILABLE]${NC}" || echo "${RED}[ALREADY IN USE]${NC}") \n"
  if ! $(port_open $CHE_PORT); then
    error "Ports required to run $CHE_MINI_PRODUCT_NAME are used by another program. Aborting..."
    return 1;
  fi
  text "\n"

    # Start Eclipse Che
    # Note bug in docker requires relative path, not absolute path to compose file
    info "start" "Starting containers..."
    log "docker_compose --file=\"${REFERENCE_CONTAINER_COMPOSE_FILE}\" -p=$CHE_MINI_PRODUCT_NAME up -d >> \"${LOGS}\" 2>&1"
    docker_compose --file="${REFERENCE_CONTAINER_COMPOSE_FILE}" \
                   -p=$CHE_MINI_PRODUCT_NAME up -d >> "${LOGS}" 2>&1
    check_if_booted
  }


cmd_stop() {
  debug $FUNCNAME

  if [ $# -gt 0 ]; then
    error "${CHE_MINI_PRODUCT_NAME} stop: You passed unknown options. Aborting."
    return
  fi

  info "stop" "Stopping containers..."
  log "docker_compose --file=\"${REFERENCE_CONTAINER_COMPOSE_FILE}\" -p=$CHE_MINI_PRODUCT_NAME stop >> \"${LOGS}\" 2>&1 || true"
  docker_compose --file="${REFERENCE_CONTAINER_COMPOSE_FILE}" \
                 -p=$CHE_MINI_PRODUCT_NAME stop >> "${LOGS}" 2>&1 || true
  info "stop" "Removing containers..."
  log "y | docker_compose --file=\"${REFERENCE_CONTAINER_COMPOSE_FILE}\" -p=$CHE_MINI_PRODUCT_NAME rm >> \"${LOGS}\" 2>&1 || true"
  docker_compose --file="${REFERENCE_CONTAINER_COMPOSE_FILE}" \
                 -p=$CHE_MINI_PRODUCT_NAME rm --force >> "${LOGS}" 2>&1 || true
}

cmd_restart() {
  debug $FUNCNAME

  FORCE_UPDATE=${1:-"--no-force"}
    info "restart" "Restarting..."
    cmd_stop
    cmd_start ${FORCE_UPDATE}
}

cmd_destroy() {
  debug $FUNCNAME

  WARNING="destroy !!! Stopping services and !!! deleting data !!! this is unrecoverable !!!"
  if ! confirm_operation "${WARNING}" "$@"; then
    return;
  fi

  # Stop alls services
  cmd_stop

  info "destroy" "Deleting instance and config..."
  log "docker_run -v \"${CHE_HOST_CONFIG}\":/che-config -v \"${CHE_HOST_INSTANCE}\":/che-instance alpine:3.4 sh -c \"rm -rf /root/che-instance/* && rm -rf /root/che-config/*\""
  docker_run -v "${CHE_HOST_CONFIG}":/root/che-config \
             -v "${CHE_HOST_INSTANCE}":/root/che-instance \
                alpine:3.4 sh -c "rm -rf /root/che-instance/* && rm -rf /root/che-config/*"
  LOG_INITIALIZED=false
  rm -rf "${CHE_CONTAINER_CONFIG}"
  rm -rf "${CHE_CONTAINER_INSTANCE}"
}

cmd_rmi() {
  info "rmi" "Checking registry for version '$CHE_VERSION' images"
  if ! has_version_registry $CHE_VERSION; then
    version_error $CHE_VERSION
    return 1;
  fi

  WARNING="rmi !!! Removing images disables che and forces a pull !!!"
  if ! confirm_operation "${WARNING}" "$@"; then
    return;
  fi

  IMAGE_LIST=$(cat "$CHE_MANIFEST_DIR"/$CHE_VERSION/images)
  IFS=$'\n'
  info "rmi" "Removing ${CHE_MINI_PRODUCT_NAME} Docker images..."

  for SINGLE_IMAGE in $IMAGE_LIST; do
    VALUE_IMAGE=$(echo $SINGLE_IMAGE | cut -d'=' -f2)
    info "rmi" "Removing $VALUE_IMAGE..."
    log "docker rmi -f ${VALUE_IMAGE} >> \"${LOGS}\" 2>&1 || true"
    docker rmi -f $VALUE_IMAGE >> "${LOGS}" 2>&1 || true
  done

  # This is Eclipse's singleton instance with the version registry
  info "rmi" "Removing $CHE_GLOBAL_VERSION_IMAGE"
  docker rmi -f $CHE_GLOBAL_VERSION_IMAGE >> "${LOGS}" 2>&1 || true
}


cmd_upgrade() {
  debug $FUNCNAME
  info "upgrade" "Not yet implemented"

  if [ $# -eq 0 ]; then
    info "upgrade" "No upgrade target provided. Run '${CHE_MINI_PRODUCT_NAME} version' for a list of upgradeable versions."
    return 2;
  fi

  if ! can_upgrade $(get_installed_version) ${1}; then
    info "upgrade" "Your current version $(get_installed_version) is not upgradeable to $1."
    info "upgrade" "Run '${CHE_MINI_PRODUCT_NAME} version' to see your upgrade options."
    return 2;
  fi

  # If here, this version is validly upgradeable.  You can upgrade from
  # $(get_installed_version) to $1
  echo "remove me -- you entered a version that you can upgrade to"

}

cmd_version() {
  debug $FUNCNAME

  error "!!! this information is experimental - upgrade not yet available !!!"
  echo ""
  text "$CHE_PRODUCT_NAME:\n"
  text "  Version:      %s\n" $(get_installed_version)
  text "  Installed:    %s\n" $(get_installed_installdate)

  if is_initialized; then
    text "\n"
    text "Upgrade Options:\n"
    text "  INSTALLED VERSION        UPRADEABLE TO\n"
    print_upgrade_manifest $(get_installed_version)
  fi

  text "\n"
  text "Available:\n"
  text "  VERSION                  CHANNEL           UPGRADEABLE FROM\n"
  if is_initialized; then
    print_version_manifest $(get_installed_version)
  else
    print_version_manifest $CHE_VERSION
  fi
}

cmd_backup() {
  debug $FUNCNAME

  # possibility to skip che projects backup
  SKIP_BACKUP_CHE_DATA=${1:-"--no-skip-data"}
  if [[ "${SKIP_BACKUP_CHE_DATA}" == "--skip-data" ]]; then
    TAR_EXTRA_EXCLUDE="--exclude=data/che"
  else
    TAR_EXTRA_EXCLUDE=""
  fi

  if [[ ! -d "${CHE_CONTAINER_CONFIG}" ]] || \
     [[ ! -d "${CHE_CONTAINER_INSTANCE}" ]]; then
    error "Cannot find existing CHE_CONFIG or CHE_INSTANCE."
    return;
  fi

  if get_server_container_id "${CHE_SERVER_CONTAINER_NAME}" >> "${LOGS}" 2>&1; then
    error "$CHE_MINI_PRODUCT_NAME is running. Stop before performing a backup."
    return 2;
  fi

  if [[ ! -d "${CHE_CONTAINER_BACKUP}" ]]; then
    mkdir -p "${CHE_CONTAINER_BACKUP}"
  fi

  # check if backups already exist and if so we move it with time stamp in name
  if [[ -f "${CHE_CONTAINER_BACKUP}/${CHE_CONFIG_BACKUP_FILE_NAME}" ]]; then
    mv "${CHE_CONTAINER_BACKUP}/${CHE_CONFIG_BACKUP_FILE_NAME}" \
        "${CHE_CONTAINER_BACKUP}/moved-$(get_current_date)-${CHE_CONFIG_BACKUP_FILE_NAME}"
  fi
  if [[ -f "${CHE_CONTAINER_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}" ]]; then
    mv "${CHE_CONTAINER_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}" \
        "${CHE_CONTAINER_BACKUP}/moved-$(get_current_date)-${CHE_INSTANCE_BACKUP_FILE_NAME}"
  fi

  info "backup" "Saving configuration..."
  docker_run -v "${CHE_HOST_CONFIG}":/root/che-config \
             -v "${CHE_HOST_BACKUP}":/root/backup \
                 alpine:3.4 sh -c "tar czf /root/backup/${CHE_CONFIG_BACKUP_FILE_NAME} -C /root/che-config ."

  info "backup" "Saving instance data..."
  # if windows we backup data volume
  if has_docker_for_windows_client; then
    docker_run -v "${CHE_HOST_INSTANCE}":/root/che-instance \
               -v "${CHE_HOST_BACKUP}":/root/backup \
               -v che-postgresql-volume:/root/che-instance/data/postgres \
                 alpine:3.4 sh -c "tar czf /root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME} -C /root/che-instance . --exclude=logs ${TAR_EXTRA_EXCLUDE}"
  else
    docker_run -v "${CHE_HOST_INSTANCE}":/root/che-instance \
              -v "${CHE_HOST_BACKUP}":/root/backup \
                 alpine:3.4 sh -c "tar czf /root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME} -C /root/che-instance . --exclude=logs ${TAR_EXTRA_EXCLUDE}"
  fi

  info ""
  info "backup" "Configuration data saved in ${CHE_HOST_BACKUP}/${CHE_CONFIG_BACKUP_FILE_NAME}"
  info "backup" "Instance data saved in ${CHE_HOST_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}"
}

cmd_restore() {
  debug $FUNCNAME

  if [[ -d "${CHE_CONTAINER_CONFIG}" ]] || \
     [[ -d "${CHE_CONTAINER_INSTANCE}" ]]; then

    WARNING="Restoration overwrites existing configuration and data. Are you sure?"
    if ! confirm_operation "${WARNING}" "$@"; then
      return;
    fi
  fi

  if get_server_container_id "${CHE_SERVER_CONTAINER_NAME}" >> "${LOGS}" 2>&1; then
    error "Eclipse Che is running. Stop before performing a restore. Aborting"
    return;
  fi

  if [[ ! -f "${CHE_CONTAINER_BACKUP}/${CHE_CONFIG_BACKUP_FILE_NAME}" ]] || \
     [[ ! -f "${CHE_CONTAINER_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}" ]]; then
    error "Backup files not found. To do restore please do backup first."
    return;
  fi

  # remove config and instance folders
  log "docker_run -v \"${CHE_HOST_CONFIG}\":/che-config \
                  -v \"${CHE_HOST_INSTANCE}\":/che-instance \
                    alpine:3.4 sh -c \"rm -rf /root/che-instance/* \
                                   && rm -rf /root/che-config/*\""
  docker_run -v "${CHE_HOST_CONFIG}":/root/che-config \
             -v "${CHE_HOST_INSTANCE}":/root/che-instance \
                alpine:3.4 sh -c "rm -rf /root/che-instance/* \
                              && rm -rf /root/che-config/*"
  log "rm -rf \"${CHE_CONTAINER_CONFIG}\" >> \"${LOGS}\""
  log "rm -rf \"${CHE_CONTAINER_INSTANCE}\" >> \"${LOGS}\""
  rm -rf "${CHE_CONTAINER_CONFIG}"
  rm -rf "${CHE_CONTAINER_INSTANCE}"

  info "restore" "Recovering configuration..."
  mkdir -p "${CHE_CONTAINER_CONFIG}"
  docker_run -v "${CHE_HOST_CONFIG}":/root/che-config \
             -v "${CHE_HOST_BACKUP}/${CHE_CONFIG_BACKUP_FILE_NAME}":"/root/backup/${CHE_CONFIG_BACKUP_FILE_NAME}" \
               alpine:3.4 sh -c "tar xf /root/backup/${CHE_CONFIG_BACKUP_FILE_NAME} \
                             -C /root/che-config"

  info "restore" "Recovering instance data..."
  mkdir -p "${CHE_CONTAINER_INSTANCE}"
  if has_docker_for_windows_client; then
    log "docker volume rm che-postgresql-volume >> \"${LOGS}\" 2>&1 || true"
    docker volume rm che-postgresql-volume >> "${LOGS}" 2>&1 || true
    log "docker volume create --name=che-postgresql-volume >> \"${LOGS}\""
    docker volume create --name=che-postgresql-volume >> "${LOGS}"
    docker_run -v "${CHE_HOST_INSTANCE}":/root/che-instance \
               -v "${CHE_HOST_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}":"/root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME}" \
              -v che-postgresql-volume:/root/che-instance/data/postgres \
                 alpine:3.4 sh -c "tar xf /root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME} -C /root/che-instance"
  else
    docker_run -v "${CHE_HOST_INSTANCE}":/root/che-instance \
               -v "${CHE_HOST_BACKUP}/${CHE_INSTANCE_BACKUP_FILE_NAME}":"/root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME}" \
                 alpine:3.4 sh -c "tar xf /root/backup/${CHE_INSTANCE_BACKUP_FILE_NAME} -C /root/che-instance"
  fi
}

cmd_offline() {
  info "offline" "Checking registry for version '$CHE_VERSION' images"
  if ! has_version_registry $CHE_VERSION; then
    version_error $CHE_VERSION
    return 1;
  fi

  # Make sure the images have been pulled and are in your local Docker registry
  cmd_download

  mkdir -p $CHE_OFFLINE_FOLDER

  IMAGE_LIST=$(cat "$CHE_MANIFEST_DIR"/$CHE_VERSION/images)
  IFS=$'\n'
  info "offline" "Saving ${CHE_MINI_PRODUCT_NAME} Docker images as tar files..."

  for SINGLE_IMAGE in $IMAGE_LIST; do
    VALUE_IMAGE=$(echo $SINGLE_IMAGE | cut -d'=' -f2)
    TAR_NAME=$(echo $VALUE_IMAGE | sed "s|\/|_|")
    info "offline" "Saving $CHE_HOST_BACKUP/$TAR_NAME.tar..."
    if ! $(docker save $VALUE_IMAGE > $CHE_OFFLINE_FOLDER/$TAR_NAME.tar); then
      error "Docker was interrupted while saving $CHE_OFFLINE_FOLDER/$TAR_NAME.tar"
      return 1;
    fi
  done

  info "offline" "Done!"
}


cmd_info() {
  debug $FUNCNAME
  if [ $# -eq 0 ]; then
    TESTS="--debug"
  else
    TESTS=$1
  fi

  case $TESTS in
    --all|-all)
      cmd_debug
      cmd_network
    ;;
    --network|-network)
      cmd_network
    ;;
    --debug|-debug)
      cmd_debug
    ;;
    *)
      info "info" "Unknown info flag passed: $1."
      return;
    ;;
  esac
}

cmd_debug() {
  debug $FUNCNAME
  info "---------------------------------------"
  info "------------   CLI INFO   -------------"
  info "---------------------------------------"
  info ""
  info "-----------  CHE INFO  ------------"
  info "CHE_VERSION           = ${CHE_VERSION}"
  info "CHE_INSTANCE          = ${CHE_HOST_INSTANCE}"
  info "CHE_CONFIG            = ${CHE_HOST_CONFIG}"
  info "CHE_HOST              = ${CHE_HOST}"
  info "CHE_REGISTRY          = ${CHE_MANIFEST_DIR}"
  info "CHE_DEVELOPMENT_MODE  = ${CHE_DEVELOPMENT_MODE}"
  if [ "${CHE_DEVELOPMENT_MODE}" = "on" ]; then
    info "CHE_DEVELOPMENT_REPO  = ${CHE_HOST_DEVELOPMENT_REPO}"
  fi
  info "CHE_BACKUP            = ${CHE_HOST_BACKUP}"
  info ""
  info "-----------  PLATFORM INFO  -----------"
  info "DOCKER_INSTALL_TYPE       = $(get_docker_install_type)"
  info "IS_NATIVE                 = $(is_native && echo "YES" || echo "NO")"
  info "IS_WINDOWS                = $(has_docker_for_windows_client && echo "YES" || echo "NO")"
  info "IS_DOCKER_FOR_WINDOWS     = $(is_docker_for_windows && echo "YES" || echo "NO")"
  info "HAS_DOCKER_FOR_WINDOWS_IP = $(has_docker_for_windows_client && echo "YES" || echo "NO")"
  info "IS_DOCKER_FOR_MAC         = $(is_docker_for_mac && echo "YES" || echo "NO")"
  info "IS_BOOT2DOCKER            = $(is_boot2docker && echo "YES" || echo "NO")"
  info ""
}

cmd_network() {
  debug $FUNCNAME

  if [ -z ${IMAGE_PUPPET+x} ]; then
    get_image_manifest $CHE_VERSION
  fi

  info ""
  info "---------------------------------------"
  info "--------   CONNECTIVITY TEST   --------"
  info "---------------------------------------"
  # Start a fake workspace agent
  log "docker run -d -p 12345:80 --name fakeagent alpine:3.4 httpd -f -p 80 -h /etc/ >> \"${LOGS}\""
  docker run -d -p 12345:80 --name fakeagent alpine:3.4 httpd -f -p 80 -h /etc/ >> "${LOGS}"

  AGENT_INTERNAL_IP=$(docker inspect --format='{{.NetworkSettings.IPAddress}}' fakeagent)
  AGENT_INTERNAL_PORT=80
  AGENT_EXTERNAL_IP=$CHE_HOST
  AGENT_EXTERNAL_PORT=12345


  ### TEST 1: Simulate browser ==> workspace agent HTTP connectivity
  HTTP_CODE=$(curl -I localhost:${AGENT_EXTERNAL_PORT}/alpine-release \
                          -s -o "${LOGS}" --connect-timeout 5 \
                          --write-out "%{http_code}") || echo "28" >> "${LOGS}"

  if [ "${HTTP_CODE}" = "200" ]; then
      info "Browser    => Workspace Agent (localhost): Connection succeeded"
  else
      info "Browser    => Workspace Agent (localhost): Connection failed"
  fi

  ### TEST 1a: Simulate browser ==> workspace agent HTTP connectivity
  HTTP_CODE=$(curl -I ${AGENT_EXTERNAL_IP}:${AGENT_EXTERNAL_PORT}/alpine-release \
                          -s -o "${LOGS}" --connect-timeout 5 \
                          --write-out "%{http_code}") || echo "28" >> "${LOGS}"

  if [ "${HTTP_CODE}" = "200" ]; then
      info "Browser    => Workspace Agent ($AGENT_EXTERNAL_IP): Connection succeeded"
  else
      info "Browser    => Workspace Agent ($AGENT_EXTERNAL_IP): Connection failed"
  fi

  ### TEST 2: Simulate Che server ==> workspace agent (external IP) connectivity
  export HTTP_CODE=$(docker_run --name fakeserver \
                                --entrypoint=curl \
                                ${IMAGE_CHE} \
                                  -I ${AGENT_EXTERNAL_IP}:${AGENT_EXTERNAL_PORT}/alpine-release \
                                  -s -o "${LOGS}" \
                                  --write-out "%{http_code}")

  if [ "${HTTP_CODE}" = "200" ]; then
      info "Server     => Workspace Agent (External IP): Connection succeeded"
  else
      info "Server     => Workspace Agent (External IP): Connection failed"
  fi

  ### TEST 3: Simulate Che server ==> workspace agent (internal IP) connectivity
  export HTTP_CODE=$(docker_run --name fakeserver \
                                --entrypoint=curl \
                                ${IMAGE_CHE} \
                                  -I ${AGENT_INTERNAL_IP}:${AGENT_INTERNAL_PORT}/alpine-release \
                                  -s -o "${LOGS}" \
                                  --write-out "%{http_code}")

  if [ "${HTTP_CODE}" = "200" ]; then
      info "Server     => Workspace Agent (Internal IP): Connection succeeded"
  else
      info "Server     => Workspace Agent (Internal IP): Connection failed"
  fi

  log "docker rm -f fakeagent >> \"${LOGS}\""
  docker rm -f fakeagent >> "${LOGS}"
}
