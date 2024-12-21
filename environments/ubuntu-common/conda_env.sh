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


# TASK [Handle the specified event]

case "${EVENT_TYPE}" in
  activate)
    
    # TASK [Initialize environment variables]

    export JUGGLEBOT_REPO_DIR="${HOME}/Jugglebot"
    export JUGGLEBOT_CONFIG_DIR="${HOME}/.jugglebot"
    export ROS_DOMAIN_ID="$(yq -r .ros.domain_id "${JUGGLEBOT_CONFIG_DIR}/jugglebot_rc.yml")"
    export DISPLAY=':0'

    # TASK [Determine the ROS2 setup script filepath]

    ROS_CODENAME="$(yq -r .ros.version_codename "${JUGGLEBOT_CONFIG_DIR}/jugglebot_rc.yml")"
    ROS_SETUP_FILEPATH="/opt/ros/${ROS_CODENAME}/setup.zsh"
    
    # TASK [Enable ROS2 by sourcing its setup script into the shell environment]

    if [[ "${ROS_WORKAROUND_ENABLED:-no}" == 'yes' ]]; then
      echo '[INFO]: The ROS2 environment init is skipped during the host setup'
    elif [[ -f "${ROS_SETUP_FILEPATH}" ]]; then
      source "${ROS_SETUP_FILEPATH}"
    else
      echo '[WARNING]: The ROS2 setup script was not found.'
    fi
    ;;
  
  deactivate)
  
    # TASK [Cleanup environment variables]

    unset JUGGLEBOT_REPO_DIR
    unset JUGGLEBOT_CONFIG_DIR
    unset ROS_DOMAIN_ID

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

