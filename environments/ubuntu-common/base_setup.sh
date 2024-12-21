# TASK [Educate about why a Bash shebang line isn't here]
#
# This file is intended to be sourced by another bash script. Sourcing enables the
# sourcing setup script to immediately use the conda environment that this script
# provisions and enables. More specifically, it enables the sourcing script to run
# ansible-playbook immediately.

# TASK [Include the strict Bash header]

set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # Stricter IFS settings
rc=0

# TASK [Define functions]

task() {
  local task_desc="$1"
  echo -e "\nTASK [${task_desc}] ********"
}

task 'Assert that a jugglebot Conda env config file was specified'

if [[ -z "${JUGGLEBOT_CONDA_ENV_FILEPATH:-}" ]]; then
  echo -e '[ERROR]: A jugglebot Conda env config file is required. Set\nJUGGLEBOT_CONDA_ENV_FILEPATH before sourcing this script.'
  exit 2
fi

task 'Initialize variables'

HOST_SETUP_DIR="${HOME}/.jugglebot/host_setup"
HOST_SETUP_BACKUPS_DIR="${HOME}/.jugglebot/host_setup/backups"
CONDA_SETUP_SCRIPT_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$( uname )-$( uname -m ).sh"
CONDA_SETUP_SCRIPT_FILEPATH="${HOST_SETUP_DIR}/miniforge_setup.sh"
CONDA_FILEPATH="${HOME}/miniforge3/bin/conda"

task 'Ensure that the ~/.jugglebot/host_setup/backups directory exists'

install -d "${HOST_SETUP_BACKUPS_DIR}"

task 'Download the conda setup script'

# when: the setup script doesn't exist

if [[ ! -f "${CONDA_SETUP_SCRIPT_FILEPATH}" ]]; then
  wget "${CONDA_SETUP_SCRIPT_URL}" -O - > "${CONDA_SETUP_SCRIPT_FILEPATH}" || rc="$?"
fi

# failed_when: the return code is nonzero

if [[ $rc -ne 0 ]]; then
  echo "[ERROR]: The Conda setup script could not be downloaded from `${CONDA_SETUP_SCRIPT_URL}`."
  exit $rc
fi

task 'Run the conda setup script'

if [[ ! -f "${CONDA_FILEPATH}" ]]; then
  # The `-b` flag signifies batch mode, which applies the default config.
  sh "${CONDA_SETUP_SCRIPT_FILEPATH}" -b 
fi

# failed_when: the setup script didn't produce the conda executable

if [[ ! -f "${CONDA_FILEPATH}" ]]; then
  echo "[ERROR]: The Conda setup script did not provision `${CONDA_FILEPATH}`."
  exit 3
fi

task 'Install conda in the bashrc'

"${CONDA_FILEPATH}" init bash || true

task 'Enable conda'

eval "$("${CONDA_FILEPATH}" 'shell.bash' 'hook' 2> /dev/null)"

task 'Update conda base'

conda update -y -n base -c conda-forge conda

task 'Determine whether the jugglebot conda environment exists'

JUGGLEBOT_CONDA_ENV_STATE="$( if conda info --envs | grep -q '^jugglebot\s'; then echo 'present'; else echo 'absent'; fi )"

if [[ "${JUGGLEBOT_CONDA_ENV_STATE}" == 'absent' ]]; then

  task 'Create the jugglebot conda environment'

  conda env create -f "${JUGGLEBOT_CONDA_ENV_FILEPATH}"

else

  JUGGLEBOT_CONDA_ENV_BACKUP_FILEPATH="$( mktemp -p "${HOST_SETUP_BACKUPS_DIR}" "jugglebot_conda_env.$( date +'%Y-%m-%dT%H-%M-%S%z' )_XXXXXXXX.yml" )"
 
  task 'Backup the jugglebot conda environment config to ~/.jugglebot/host_setup/backups'

  conda env export --from-history > "${JUGGLEBOT_CONDA_ENV_BACKUP_FILEPATH}"

  task 'Update the jugglebot conda environment'

  conda env update -f "${JUGGLEBOT_CONDA_ENV_FILEPATH}" --prune

fi

task 'Activate the jugglebot conda environment'

export ROS_WORKAROUND_ENABLED=yes

conda activate jugglebot

unset ROS_WORKAROUND_ENABLED

task 'Disable shell prompt modification by conda'

conda config --set changeps1 False

