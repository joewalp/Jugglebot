# TASK [Educate about how this script is invoked]
#
# Upon activating/deactivating the jugglebot conda environment, one of the
# following two scripts is sourced, respectively.
#
# ~/miniforge3/envs/jugglebot/etc/conda/activate.d/conda_env_activate.sh
# ~/miniforge3/envs/jugglebot/etc/conda/deactivate.d/conda_env_deactivate.sh
#
# Each of those scripts sets the relevant EVENT_TYPE and then sources this
# script.

# TASK [Define functions]

enable_ros2() {
  local jugglebot_rc_filepath="$1"
  local ros_codename="$(yq -r .ros.version_codename "${jugglebot_rc_filepath}")"
  local ros_setup_filepath="/opt/ros/${ros_codename}/setup.zsh"

  # TASK [Source the ROS2 setup script into the shell environment]

  if [[ -f "${ros_setup_filepath}" ]]; then
    source "${ros_setup_filepath}"
  else
    echo '[WARNING]: The ROS2 setup script was not found.'
  fi
}

# TASK [Handle the specified event]

case "${EVENT_TYPE}" in
  activate)
    
    # TASK [Initialize environment variables]

    export JUGGLEBOT_REPO_DIR="${HOME}/Jugglebot"
    export JUGGLEBOT_CONFIG_DIR="${HOME}/.jugglebot"
  
    # TASK [Enable ROS2]

    enable_ros2 "${JUGGLEBOT_CONFIG_DIR}/jugglebot_rc.yml"
    ;;
  
  deactivate)
  
    # TASK [Cleanup environment variables]

    unset JUGGLEBOT_REPO_DIR
    unset JUGGLEBOT_CONFIG_DIR

    # TASK [Disable ROS2]
    #
    # TODO Stop ROS2 and remove its environment variables
    #
    # A comprehensive treatment of this nice-to-have environment cleanup
    # feature may end up introducing dependencies on the ROS2 internals. Let's
    # defer implementation until we have some need to clean up the environment
    # upon deactivating.
    ;;

  *)
    echo -e "\n[ERROR]: Unrecognized event type (${EVENT_TYPE})."
    exit 2
    ;;
esac

