# TASK [Educate about why a Bash shebang line isn't here]
#
# This file is intended to be sourced by another bash script. Sourcing enables the
# sourcing setup script to immediately use the conda environment that this script
# provisions and enables. More specifically, it enables the sourcing script to run
# ansible-playbook immediately.

# TASK [Include the strict Bash header]

set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

# TASK [Define functions]

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

task 'Assert that a jugglebot Conda env config file was specified'

if [[ -z "${JUGGLEBOT_CONDA_ENV_FILEPATH:-}" ]]; then
  echo -e '[ERROR]: A jugglebot Conda env config file is required. Set\nJUGGLEBOT_CONDA_ENV_FILEPATH before sourcing this script.' >&2
  exit 2
fi

task 'Initialize variables'

REFRESH_HOST_PROVISIONING_ENV_ENABLED="${REFRESH_HOST_PROVISIONING_ENV_ENABLED:-yes}"
REFRESH_JUGGLEBOT_ENV_ENABLED="${REFRESH_JUGGLEBOT_ENV_ENABLED:-yes}"
CONDA_SETUP_SCRIPT_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$( uname )-$( uname -m ).sh"
HOST_SETUP_DIR="${HOME}/.jugglebot/host_setup"
CONDA_SETUP_SCRIPT_FILEPATH="${HOME}/.jugglebot/host_setup/miniforge_setup.sh"
CONDA_FILEPATH="${HOME}/miniforge3/bin/conda"
JUGGLEBOT_REPO_DIR="${JUGGLEBOT_REPO_DIR:-${HOME}/Jugglebot}"

task 'Ensure that the host setup directory exists'

install -d "${HOST_SETUP_DIR}"

task 'Download the conda setup script'

# when: the setup script doesn't exist

if [[ ! -f "${CONDA_SETUP_SCRIPT_FILEPATH}" ]]; then
  wget "${CONDA_SETUP_SCRIPT_URL}" -O - > "${CONDA_SETUP_SCRIPT_FILEPATH}" || rc="$?"
fi

# failed_when: the return code is nonzero

if [[ $rc -ne 0 ]]; then
  echo "[ERROR]: The Conda setup script could not be downloaded from `${CONDA_SETUP_SCRIPT_URL}`." >&2
  exit $rc
fi

task 'Run the Conda setup script'

if [[ ! -f "${CONDA_FILEPATH}" ]]; then
  # The `-b` flag signifies batch mode, which applies the default config.
  sh "${CONDA_SETUP_SCRIPT_FILEPATH}" -b 
fi

# failed_when: the setup script didn't produce the conda executable

if [[ ! -f "${CONDA_FILEPATH}" ]]; then
  echo "[ERROR]: The Conda setup script did not provision `${CONDA_FILEPATH}`." >&2
  exit 3
fi

"${JUGGLEBOT_REPO_DIR}/environments/ubuntu-common/refresh-dependencies" \
  --refresh-host-provisioning-conda-env "${REFRESH_HOST_PROVISIONING_ENV_ENABLED}" \
  --refresh-jugglebot-conda-env "${REFRESH_JUGGLEBOT_ENV_ENABLED}"
  

eval "$("${CONDA_FILEPATH}" 'shell.bash' 'hook' 2> /dev/null)"

conda activate host-provisioning

