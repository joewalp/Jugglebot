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
    -e|--environments-dir)
      ENVIRONMENTS_DIR="$2"
      shift
      shift
      ;;
    -w|--ros-workspace-dir)
      ROS_WORKSPACE_DIR="$2"
      shift
      shift
      ;;
    -c|--jugglebot-conda-env-filepath)
      JUGGLEBOT_CONDA_ENV_FILEPATH="$2"
      shift
      shift
      ;;
    -p|--ansible-become-pass)
      ANSIBLE_BECOME_PASS="$2"
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

task 'Assert that the environments directory was specified'

if [[ -z "${ENVIRONMENTS_DIR:-}" ]]; then
  echo '[ERROR]: The environments directory is required. Invoke this command with the `--environments-dir "[directory path]"` option.' >&2
  exit 2
fi

task 'Assert that the ROS workspace directory was specified'

if [[ -z "${ROS_WORKSPACE_DIR:-}" ]]; then
  echo '[ERROR]: The ROS workspace directory is required. Invoke this command with the `--ros-workspace-dir "[directory path]"` option.' >&2
  exit 2
fi

task 'Assert that a conda environment config file was specified'

if [[ -z "${JUGGLEBOT_CONDA_ENV_FILEPATH:-}" ]]; then
  echo '[ERROR]: The jugglebot conda env config file is required. Invoke this command with the `--jugglebot-conda-env-filepath "[conda environment config file]"` option.' >&2
  exit 2
fi

task 'Assert that the Ansible become password was specified'

if [[ -z "${ANSIBLE_BECOME_PASS:-}" ]]; then
  echo '[ERROR]: Ansible become password is required. Invoke this command with the `--ansible-become-pass "[cleartext password]"` option.' >&2
  exit 2
fi

task 'Source base_setup.sh'

# Note: This requires JUGGLEBOT_CONDA_ENV_FILEPATH to be set.

source "${ENVIRONMENTS_DIR}/ubuntu-common/base_setup.sh"

task 'Run the playbook'

ANSIBLE_LOCALHOST_WARNING=False \
  ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
  ANSIBLE_BECOME_PASS="${ANSIBLE_BECOME_PASS}" \
  ansible-playbook "${ENVIRONMENTS_DIR}/ubuntu-docker/main_playbook.yml" \
    -e upgrade_software=yes \
    -e "ros_workspace_dir=${ROS_WORKSPACE_DIR}"
