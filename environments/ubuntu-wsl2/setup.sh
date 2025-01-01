#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

EX_UNAVAILABLE=69
EX_OSFILE=72

# TASK [Define functions]

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

task 'Parse the arguments'

while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--upgrade)
      UPGRADE_MODE_ENABLED='yes'
      shift
      shift
      ;;
    -i)
      SSH_IDENTITY_FILEPATH="$2"
      shift
      shift
      ;;
    -N|--git-name)
      GIT_NAME="$2"
      shift
      shift
      ;;
    -E|--git-email)
      GIT_EMAIL="$2"
      shift
      shift
      ;;
    --refresh-host-provisioning-conda-env)
      REFRESH_HOST_PROVISIONING_ENV_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --refresh-jugglebot-conda-env)
      REFRESH_JUGGLEBOT_ENV_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --clone-repo)
      CLONE_REPO_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --debug-repo-dir)
      DEBUG_REPO_DIR="$2"
      shift
      shift
      ;;
    -*|--*)
      echo "[ERROR]: Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

task 'Initialize variables'

JUGGLEBOT_CONFIG_DIR="${JUGGLEBOT_CONFIG_DIR:-${HOME}/.jugglebot}"
JUGGLEBOT_CONFIG_FILEPATH="${JUGGLEBOT_CONFIG_DIR}/config.yml"

task 'Determine whether upgrade mode is enabled'

UPGRADE_MODE_ENABLED="${UPGRADE_MODE_ENABLED:-no}"

task 'Assert that an ssh identity file was specified'

if [[ -z "${SSH_IDENTITY_FILEPATH:-}" ]]; then

  if [[ "${UPGRADE_MODE_ENABLED}" == 'yes' ]]; then
    if which yq >/dev/null 2>&1 ; then
      SSH_IDENTITY_FILEPATH="$( yq -r .ssh.github_com.identity_filepath \
        "${JUGGLEBOT_CONFIG_FILEPATH}" )"
    else
      echo '[ERROR]: The yq utility is not available. Upgrade mode cannot be \
used until yq has been provisioned.' >&2
      exit $EX_UNAVAILABLE
    fi
  else
    echo '[ERROR]: An ssh identity file is required when the `--upgrade` \
option is not specified. Invoke this command with the `-i [identity file]` \
switch (eg. `-i ~/.ssh/ed25519`)' >&2
    exit 2
  fi
fi

task 'Assert that the ssh identity file exists'

if [[ ! -f "${SSH_IDENTITY_FILEPATH}" ]]; then
  echo "[ERROR]: The identity file ${SSH_IDENTITY_FILEPATH} does not exist." >&2
  exit $EX_OSFILE
fi

task 'Assert that a git name was specified'

if [[ -z "${GIT_NAME:-}" && "${UPGRADE_MODE_ENABLED}" == 'no' ]]; then
  echo '[ERROR]: A git name is required when the `--upgrade` option is not specified. Invoke this command with the `--git-name "[Your full name]"` switch (eg. `--git-name "Jane Doe"`)' >&2
  exit 2
fi

GIT_NAME="${GIT_NAME:-}"

task 'Assert that a git email was specified'

if [[ -z "${GIT_EMAIL:-}" && "${UPGRADE_MODE_ENABLED}" == 'no' ]]; then
  echo '[ERROR]: A git email is required when the `--upgrade` option is not specified. Invoke this command with the `--git-email "[your email address]"` switch (eg. `--git-email "jane.doe@gmail.com"`)' >&2
  exit 2
fi

GIT_EMAIL="${GIT_EMAIL:-}"

task 'Initialize variables'

if [[ -z "${DEBUG_REPO_DIR:-}" ]]; then
  REPO_DIR="${JUGGLEBOT_REPO_DIR:-${HOME}/Jugglebot}"
else
  REPO_DIR="${DEBUG_REPO_DIR}"
  echo -e "\n[WARNING]: Specifying an alternate repo location is not supported. The '--debug-repo-dir' flag should only be used when testing this script.\n" >&2
fi

CLONE_REPO_ENABLED="${CLONE_REPO_ENABLED:-yes}"

task 'Enable ssh-agent'

eval "$(ssh-agent -s)"

task 'Add the ssh private key'

# Note: This will prompt for the passphrase if the key requires one

ssh-add "${SSH_IDENTITY_FILEPATH}"

task 'Source ubuntu-common/base_setup.sh'

source "${REPO_DIR}/environments/ubuntu-common/base_setup.sh"

task 'Run the ubuntu-wsl2 Ansible playbook'

echo -e "\nEnter your password to enable the playbook to configure this Ubuntu host"

ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ansible-playbook \
  "${REPO_DIR}/environments/ubuntu-wsl2/main_playbook.yml" \
  --ask-become-pass \
  -e "git_email='${GIT_EMAIL}'" \
  -e "git_name='${GIT_NAME}'" \
  -e "raw_clone_repo_enabled='${CLONE_REPO_ENABLED}'" \
  -e "raw_upgrade_mode_enabled='${UPGRADE_MODE_ENABLED}'" \
  -e "raw_upgrade_software_enabled='yes'" \
  -e "ssh_identity_filepath='${SSH_IDENTITY_FILEPATH}'" \
  -e "DISPLAY='${DISPLAY}'" || rc="$?"

# failed_when: the return code is nonzero

if [[ $rc -ne 0 ]]; then
  echo -e "[ERROR]: The Ansible playbook failed with return code ${rc}." >&2
  exit $rc
fi

echo -e "\nPlease exit and create a new terminal session to enable all changes\n"
