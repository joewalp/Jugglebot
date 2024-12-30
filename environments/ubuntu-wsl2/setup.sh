#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

# TASK [Define functions]

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

task 'Parse the arguments'

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--ssh-keypair-name)
      SSH_KEYPAIR_NAME="$2"
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

task 'Assert that an ssh keypair name was specified'

if [[ -z "${SSH_KEYPAIR_NAME:-}" ]]; then
  echo '[ERROR]: An ssh keypair name is required. Invoke this command with the `--ssh-keypair-name [keypair name]` switch (eg. `--ssh-keypair-name ed25519`)' >&2
  exit 2
fi

task 'Assert that a git name was specified'

if [[ -z "${GIT_NAME:-}" ]]; then
  echo '[ERROR]: A git name is required. Invoke this command with the `--git-name "[Your full name]"` switch (eg. `--git-name "Jane Doe"`)' >&2
  exit 2
fi

task 'Assert that a git email was specified'

if [[ -z "${GIT_EMAIL:-}" ]]; then
  echo '[ERROR]: A git email is required. Invoke this command with the `--git-email "[your email address]"` switch (eg. `--git-email "jane.doe@gmail.com"`)' >&2
  exit 2
fi

task 'Initialize variables'

if [[ -z "${DEBUG_REPO_DIR:-}" ]]; then
  JUGGLEBOT_REPO_DIR="${JUGGLEBOT_REPO_DIR:-${HOME}/Jugglebot}"
else
  JUGGLEBOT_REPO_DIR="${DEBUG_REPO_DIR}"
  echo -e "\n[WARNING]: Specifying an alternate repo location is not supported. The '--debug-repo-dir' flag should only be used when testing this script.\n" >&2
fi

JUGGLEBOT_CONDA_ENV_FILEPATH="${JUGGLEBOT_REPO_DIR}/ros_ws/conda_env.yml"
SSH_PRIVATE_KEY_FILEPATH="${HOME}/.ssh/${SSH_KEYPAIR_NAME}"
CLONE_REPO_ENABLED="${CLONE_REPO_ENABLED:-yes}"

task 'Enable ssh-agent'

eval "$(ssh-agent -s)"

task 'Add the ssh private key'

# Note: This will prompt for the passphrase if the key requires one 

ssh-add "${SSH_PRIVATE_KEY_FILEPATH}"

task 'Source ubuntu-common/base_setup.sh'

source "${JUGGLEBOT_REPO_DIR}/environments/ubuntu-common/base_setup.sh"

task 'Run the ubuntu-wsl2 Ansible playbook'

echo -e "\nEnter your password to enable the playbook to configure this Ubuntu host"

ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ansible-playbook \
  "${JUGGLEBOT_REPO_DIR}/environments/ubuntu-wsl2/main_playbook.yml" \
  --ask-become-pass \
  -e upgrade_software=yes \
  -e "ssh_keypair_name='${SSH_KEYPAIR_NAME}'" \
  -e "git_name='${GIT_NAME}'" \
  -e "git_email='${GIT_EMAIL}'" \
  -e "clone_repo_enabled='${CLONE_REPO_ENABLED}'" \
  -e "DISPLAY='${DISPLAY}'" || rc="$?"

# failed_when: the return code is nonzero

if [[ $rc -ne 0 ]]; then
  echo -e "[ERROR]: The Ansible playbook failed with return code ${rc}." >&2
  exit $rc
fi

echo -e "\nPlease exit and create a new terminal session to enable all changes\n"
