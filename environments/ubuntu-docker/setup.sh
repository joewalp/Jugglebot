#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

# TASK [Define functions]

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

does_docker_volume_exist() {
  local volume_name="$1"
  [[ -n "$(docker volume ls --quiet --filter "name=${volume_name}")" ]]
}

is_docker_container_running() {
  local container_name="$1"
  [[ "$(docker container ls --quiet --filter "name=${container_name}")" != '' ]]
}

does_docker_container_exist() {
  local container_name="$1"
  [[ "$(docker container ls --quiet --all --filter "name=${container_name}")" != '' ]]
}

is_home_dir_initialized() {
  local container_name="$1"
  docker exec -it \
    "${container_name}" \
    /usr/bin/bash -c '[[ -f "${HOME}/.user-dir-initialized" ]]'
}

task 'Parse the arguments'

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--ssh-keypair-name)
      SSH_KEYPAIR_NAME="$2"
      shift
      shift
      ;;
    -n|--container-name)
      CONTAINER_NAME="$2"
      shift
      shift
      ;;
    --arch)
      BASE_IMAGE_ARCHITECTURE="$2"
      shift;
      shift;
      ;;
    --os-release)
      BASE_IMAGE_OS_RELEASE="$2"
      shift;
      shift;
      ;;
    -e|--debug-repo-dir)
      DEBUG_REPO_DIR="$2"
      shift
      shift
      ;;
    -b|--debug-git-branch)
      GIT_BRANCH="$2"
      shift
      shift
      ;;
    --no-cache)
      BUILD_NO_CACHE_OPTION='--no-cache'
      shift
      ;;
    --no-repo-cache)
      REPO_CACHE_ID="$(date +%s)"
      shift
      ;;
    --retain-home-volume)
      RETAIN_HOME_VOLUME="$2" # no|yes
      shift
      shift
      ;;
    -*|--*)
      echo "[ERROR]: Unknown option $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

task 'Assert that an ssh keypair name was specified'

if [[ -z "${SSH_KEYPAIR_NAME:-}" ]]; then
  echo '[ERROR]: An ssh keypair name is required. Invoke this command with the `--ssh-keypair-name [keypair name]` switch (eg. `--ssh-keypair-name ed25519`)' >&2
  exit 2
fi

task 'Determine the ROS package requirements'

BASE_IMAGE_OS_RELEASE="${BASE_IMAGE_OS_RELEASE:-focal}"

if [[ -z "${DEBUG_REPO_DIR:-}" ]]; then
  JUGGLEBOT_REPO_DIR="${JUGGLEBOT_REPO_DIR:-${HOME}/Jugglebot}"
else
  JUGGLEBOT_REPO_DIR="${DEBUG_REPO_DIR}"
  echo -e "\n[WARNING]: Specifying an alternate repo location is not supported. The '--debug-repo-dir' flag should only be used when testing this script.\n" >&2
fi

VERSION_LOOKUP_FILEPATH="${JUGGLEBOT_REPO_DIR}/environments/ubuntu-common/package_version_lookup_vars.yml"

ROS_CODENAME="$(yq -r ".ubuntu_codename_to_ros_codename.${BASE_IMAGE_OS_RELEASE}" \
  "${VERSION_LOOKUP_FILEPATH}")"

ROS_PACKAGES=('ros-dev-tools')

if [[ "${ROS_CODENAME}" == 'foxy' ]]; then
  ROS_PACKAGES+=('python3-argcomplete')
fi

ROS_PACKAGES+=("ros-${ROS_CODENAME}-desktop")
ROS_PACKAGES+=("ros-${ROS_CODENAME}-webots-ros2")

task 'Determine the Python version'

PYTHON_VERSION="$(yq -r ".ubuntu_codename_to_python_version.${BASE_IMAGE_OS_RELEASE}" \
  "${VERSION_LOOKUP_FILEPATH}")"

task 'Determine the base image and the platform option'

BASE_IMAGE_ARCHITECTURE="${BASE_IMAGE_ARCHITECTURE:-native}"

case "${BASE_IMAGE_ARCHITECTURE}" in
  native)
    BASE_IMAGE="ubuntu:${BASE_IMAGE_OS_RELEASE}"
    LOCALHOST_SSH_PORT='4022'
    DENV_EXEC_COMMAND='denv exec'
    ;;
  arm64)
    BASE_IMAGE="arm64v8/ubuntu:${BASE_IMAGE_OS_RELEASE}"
    PLATFORM_OPTION="--platform=linux/arm64"
    LOCALHOST_SSH_PORT='4122'
    DENV_EXEC_COMMAND='denv exec --arch arm64'
    ;;
  *)
    echo "[ERROR]: The specified architecture ${BASE_IMAGE_ARCHITECTURE} is not supported" >&2
    exit 2
    ;;
esac

task 'Initialize variables'

if [[ -z "${GIT_BRANCH:-}" ]]; then
  GIT_BRANCH='main'
elif [[ "${GIT_BRANCH}" != 'main' ]]; then
  echo -e "\n[WARNING]: Using git branch ${GIT_BRANCH} instead of main\n" >&2
fi

PLATFORM_OPTION="${PLATFORM_OPTION:-}"
IMAGE_NAME="jugglebot-${BASE_IMAGE_ARCHITECTURE}-dev:${BASE_IMAGE_OS_RELEASE}"
HOME_VOLUME_NAME="jugglebot-${BASE_IMAGE_ARCHITECTURE}-${BASE_IMAGE_OS_RELEASE}-dev-home"
CONTAINER_NAME="${CONTAINER_NAME:-jugglebot-${BASE_IMAGE_ARCHITECTURE}-dev}"
SSH_HOST="docker-${BASE_IMAGE_ARCHITECTURE}-env"
BUILD_NO_CACHE_OPTION="${BUILD_NO_CACHE_OPTION:-}"
REPO_CACHE_ID="${REPO_CACHE_ID:-0}"
RETAIN_HOME_VOLUME="${RETAIN_HOME_VOLUME:-no}"
DEV_ENV_USERNAME='devops' # This is also the default password for the user.
SSH_PRIVATE_KEY_FILEPATH="${HOME}/.ssh/${SSH_KEYPAIR_NAME}"
SSH_PUBLIC_KEY_FILEPATH="${HOME}/.ssh/${SSH_KEYPAIR_NAME}.pub"
BUILD_CONTEXT_DIR="${JUGGLEBOT_REPO_DIR}/environments/ubuntu-docker"

task 'Enable ssh-agent'

eval "$(ssh-agent -s)"

task 'Add the ssh private key'

# Note: This will prompt for the passphrase if the key requires one 

ssh-add "${SSH_PRIVATE_KEY_FILEPATH}"

task 'Copy the host-provisioning Conda environment file'

install -D -T "${JUGGLEBOT_REPO_DIR}/environments/ubuntu-common/host_provisioning_conda_env.yml" \
  "${BUILD_CONTEXT_DIR}/build/host_provisioning_conda_env.yml"

task 'Interpolate the jugglebot Conda environment file'

python_version="${PYTHON_VERSION}" j2 \
  -o "${BUILD_CONTEXT_DIR}/build/jugglebot_conda_env.yml" \
  -e 'python_version' "${JUGGLEBOT_REPO_DIR}/ros_ws/conda_env.yml.j2"

task 'Copy ~/.gitconfig'

install -D -T "${HOME}/.gitconfig" "${BUILD_CONTEXT_DIR}/build/gitconfig"

task "Copy ~/.ssh/${SSH_KEYPAIR_NAME}.pub"

install -D -T "${SSH_PUBLIC_KEY_FILEPATH}" \
  "${BUILD_CONTEXT_DIR}/build/ssh_authorized_keys"

task "Build the Docker image named ${IMAGE_NAME}"

docker buildx build ${BUILD_NO_CACHE_OPTION} ${PLATFORM_OPTION} \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "ROS_PACKAGE_LIST=$(IFS=' '; echo "${ROS_PACKAGES[*]}")" \
  --build-arg "USER_UID=$(id --user)" \
  --build-arg "USER_GID=$(id --group)" \
  --build-arg "DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)" \
  --build-arg "USERNAME=${DEV_ENV_USERNAME}" \
  --build-arg "JUGGLEBOT_REPO_BRANCH=${GIT_BRANCH}" \
  --build-arg "REPO_CACHE_ID=${REPO_CACHE_ID}" \
  --ssh "default=${SSH_AUTH_SOCK}" \
  --progress=tty \
  -t "${IMAGE_NAME}" \
  "${BUILD_CONTEXT_DIR}"

task 'Cleanup the build context'

rm -f "${BUILD_CONTEXT_DIR}/build/host_provisioning_conda_env.yml"
rm -f "${BUILD_CONTEXT_DIR}/build/jugglebot_conda_env.yml"
rm -f "${BUILD_CONTEXT_DIR}/build/gitconfig"
rm -f "${BUILD_CONTEXT_DIR}/build/ssh_authorized_keys"

task 'Ensure that the Docker container is not running'

if is_docker_container_running "${CONTAINER_NAME}"; then
  docker container stop "${CONTAINER_NAME}"
fi

task "Ensure that the ${CONTAINER_NAME} Docker container does not exist"

if does_docker_container_exist "${CONTAINER_NAME}"; then
  docker container rm --force --volumes "${CONTAINER_NAME}"
fi

if does_docker_volume_exist "${HOME_VOLUME_NAME}"; then
  if [[ "${RETAIN_HOME_VOLUME}" == 'no' ]]; then
    
    task "Remove the volume named ${HOME_VOLUME_NAME}"
    
    docker volume rm "${HOME_VOLUME_NAME}"

    task "Create the volume named ${HOME_VOLUME_NAME}"

    docker volume create "${HOME_VOLUME_NAME}"

  else

    task "Retain the volume named ${HOME_VOLUME_NAME}"

  fi
else
  
  task "Create the volume named ${HOME_VOLUME_NAME}"
  
  docker volume create "${HOME_VOLUME_NAME}"

fi

task "Create the ${CONTAINER_NAME} Docker container"

# Note: We expose /tmp because that is where $SSH_AUTH_SOCK is stored. We
# expose /var/run/docker.sock because that enables the container to control the
# shared Docker Engine. We expose ~/.oh-my-zsh/custom so that we can more
# easily keep aliases and shell features in sync across environments.

docker container create ${PLATFORM_OPTION} \
  --name "${CONTAINER_NAME}" \
  -v '/tmp:/tmp' \
  -v '/var/run/docker.sock:/var/run/docker.sock' \
  -v "${HOME_VOLUME_NAME}:/home" \
  -v "${HOME}/.oh-my-zsh/custom:/entrypoint/oh-my-zsh-custom" \
  -p "${LOCALHOST_SSH_PORT}:22" \
  -e "DISPLAY=${DISPLAY}" \
  --dns '8.8.8.8' \
  "${IMAGE_NAME}"

task 'Start the container to begin initializing the home directory'

docker container start "${CONTAINER_NAME}"

task 'Wait for the home directory to be initialized by entrypoint.sh'

echo -n "Initializing container ${CONTAINER_NAME} ..."

while ! is_home_dir_initialized "${CONTAINER_NAME}"; do
  sleep 2
done

echo ' done'

task 'Stop the container'

docker container stop "${CONTAINER_NAME}"

task 'Prompt next steps'

echo -e "

Run the following command to open a shell in the ${CONTAINER_NAME} container:

  ${DENV_EXEC_COMMAND}

Alternately, you can ssh into the container using the following command:

  ssh ${SSH_HOST}

---

Notes:

1. By default, the user in the container is named ${DEV_ENV_USERNAME}, and the password
   for that user is the same as the username.

2. Only the /home directory and the /tmp directory will persist across 
   container restarts. The /home directory is a mounted docker volume named 
   ${HOME_VOLUME_NAME}.

3. If you add your GitHub ssh key to the keychain prior to running
   docker-native-env, that key will be available within the container. This
   works because (a) the container shares the same /tmp directory with the
   WSL2 environment and (b) the docker-native-env script propagates the 
   SSH_AUTH_SOCK environment variable into the container. You can add the key
   to the keychain using the following command:

   ssh-add "${SSH_PRIVATE_KEY_FILEPATH}"

4. You can control the Docker Engine that is hosted by the WSL2 environment 
   from within the container. This has some security implications. Do not host
   internet-facing services within the container.

5. The ~/.oh-my-zsh/custom directory in the WSL2 environment is mounted to the 
   /home/${DEV_ENV_USERNAME}/.oh-my-zsh/custom directory in the container. This simplifies
   keeping the environments and aliases in sync.
"

