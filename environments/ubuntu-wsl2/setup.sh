#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

EX_UNAVAILABLE=69
EX_OSFILE=72

# TASK [Define functions]

print_usage() {
  echo '
usage: setup.sh [Options]

Options:
  -h|--help              Display this usage message
  -I|--install           Enable install mode, which will initialize the config
                         file at ~/.jugglebot/config.yml and provision the
                         development environment
  -e|--editor [vim|nano] Specify the preferred editor for git commits and the
                         EDITOR environment variable
  -i [ssh identity file] Specify the ssh private key that will be used for
                         GitHub and the Docker containers
  -E|--git-email [your email address]
                         Specify your name for the user.email section of
                         ~/.gitconfig
  -N|--git-name [your full name]
                         Specify your name for the user.name section of
                         ~/.gitconfig
  --x-clone-repo [yes|no]
                         Enable/disable ensuring that Jugglebot repo is cloned
                         and clean (default: yes)
  --x-refresh-host-provisioning-conda-env [yes|no]
                         Enable/disable refreshing the host-provisining Conda
                         environment (default: yes)
  --x-refresh-jugglebot-conda-env)
                         Enable/disable refreshing the jugglebot Conda
                         environment (default: yes)

'
}

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

task 'Parse the arguments'

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_usage
      exit 0
      ;;
    -e|--editor)
      EDITOR="$2"
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
    -i)
      SSH_IDENTITY_FILEPATH="$2"
      shift
      shift
      ;;
    -I|--install)
      UPGRADE_MODE_ENABLED='no'
      shift
      ;;
    --x-clone-repo)
      CLONE_REPO_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --x-refresh-host-provisioning-conda-env)
      REFRESH_HOST_PROVISIONING_ENV_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --x-refresh-jugglebot-conda-env)
      REFRESH_JUGGLEBOT_ENV_ENABLED="$2" # yes|no
      shift
      shift
      ;;
    --x-repo-dir)
      DEBUG_REPO_DIR="$2"
      shift
      shift
      ;;
    --x-upgrade-packages)
      UPGRADE_PACKAGES_ENABLED="$2"
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

EDITOR="${EDITOR:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
GIT_NAME="${GIT_NAME:-}"
SSH_IDENTITY_FILEPATH="${SSH_IDENTITY_FILEPATH:-}"
UPGRADE_MODE_ENABLED="${UPGRADE_MODE_ENABLED:-yes}"

CLONE_REPO_ENABLED="${CLONE_REPO_ENABLED:-yes}"
REFRESH_HOST_PROVISIONING_ENV_ENABLED="${REFRESH_HOST_PROVISIONING_ENV_ENABLED:-yes}"
REFRESH_JUGGLEBOT_ENV_ENABLED="${REFRESH_JUGGLEBOT_ENV_ENABLED:-yes}"
DEBUG_REPO_DIR="${DEBUG_REPO_DIR:-}"
UPGRADE_PACKAGES_ENABLED="${UPGRADE_PACKAGES_ENABLED:-yes}"

if [[ -z "${DEBUG_REPO_DIR}" ]]; then
  REPO_DIR="${JUGGLEBOT_REPO_DIR:-${HOME}/Jugglebot}"
else
  REPO_DIR="${DEBUG_REPO_DIR}"
  echo -e "\n[Warning]: Specifying an alternate repo location is not \
supported. The '--x-repo-dir' flag should only be used when testing this \
script.\n" >&2
fi

task 'Assert that an ssh identity file was specified'

if [[ -z "${SSH_IDENTITY_FILEPATH}" ]]; then

  if [[ "${UPGRADE_MODE_ENABLED}" == 'yes' ]]; then
    if which yq >/dev/null 2>&1 ; then
      SSH_IDENTITY_FILEPATH="$( yq -r .ssh.github_com.identity_filepath \
        "${JUGGLEBOT_CONFIG_FILEPATH}" )"
    else
      echo '[Error]: The yq utility is not available. Run setup.sh with the \
`--install` option.' >&2
      print_usage
      exit $EX_UNAVAILABLE
    fi
  else
    echo '[Error]: An ssh identity file is required when the `--install` \
option is specified. Invoke this command with the `-i [identity file]` \
switch (eg. `-i ~/.ssh/ed25519`)' >&2
    exit 2
  fi
fi

task 'Assert that the ssh identity file exists'

if [[ ! -f "${SSH_IDENTITY_FILEPATH}" ]]; then
  echo "[Error]: The identity file ${SSH_IDENTITY_FILEPATH} does not exist." >&2
  exit $EX_OSFILE
fi

task 'Assert that a git name was specified'

if [[ -z "${GIT_NAME}" && "${UPGRADE_MODE_ENABLED}" == 'no' ]]; then
  echo '[Error]: A git name is required when the `--install` option is \
specified. Invoke this command with the `--git-name "[Your full name]"` \
switch (eg. `--git-name "Jane Doe"`)' >&2
  exit 2
fi

task 'Assert that a git email was specified'

if [[ -z "${GIT_EMAIL}" && "${UPGRADE_MODE_ENABLED}" == 'no' ]]; then
  echo '[Error]: A git email is required when the `--install` option is \
specified. Invoke this command with the `--git-email "[your email address]"` \
switch (eg. `--git-email "jane.doe@gmail.com"`)' >&2
  exit 2
fi

if [[ -n "${EDITOR}" ]]; then
  if ! which "${EDITOR}" >/dev/null 2>&1 ; then
    echo "[Error]: The specified editor ${EDITOR} is not installed. Supported \
editors include vim [recommended] and nano. If you want to use a different \
editor, install it before running this script." >&2
    exit $EX_UNAVAILABLE
  fi
fi

task 'Enable ssh-agent'

eval "$(ssh-agent -s)"

task 'Add the ssh private key'

# Note: This will prompt for the passphrase if the key requires one

ssh-add "${SSH_IDENTITY_FILEPATH}"

task 'Source ubuntu-common/base_setup.sh'

source "${REPO_DIR}/environments/ubuntu-common/base_setup.sh"

task 'Run the ubuntu-wsl2 Ansible playbook'

echo -e "\nEnter your password to enable the playbook to configure this \
Ubuntu host"

ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
  ansible-playbook \
  "${REPO_DIR}/environments/ubuntu-wsl2/main_playbook.yml" \
  --ask-become-pass \
  -e "git_email='${GIT_EMAIL}'" \
  -e "git_name='${GIT_NAME}'" \
  -e "clone_repo_enabled__='${CLONE_REPO_ENABLED}'" \
  -e "editor='${EDITOR}'" \
  -e "upgrade_mode_enabled__='${UPGRADE_MODE_ENABLED}'" \
  -e "upgrade_packages_enabled__='${UPGRADE_PACKAGES_ENABLED}'" \
  -e "ssh_identity_filepath='${SSH_IDENTITY_FILEPATH}'" \
  -e "DISPLAY='${DISPLAY}'" || rc="$?"

# failed_when: the return code is nonzero

if [[ $rc -ne 0 ]]; then
  echo -e "[ERROR]: The Ansible playbook failed with return code ${rc}." >&2
  exit $rc
fi

echo -e "\nPlease exit and create a new terminal session to enable all \
changes\n"

