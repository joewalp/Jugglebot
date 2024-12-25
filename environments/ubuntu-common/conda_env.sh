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
    export JUGGLEBOT_RC_FILEPATH="${HOME}/.jugglebot/jugglebot_rc.yml"
    export DISPLAY=':0'

    if [[ "${ROS_WORKAROUND_ENABLED:-no}" == 'yes' ]]; then
      echo '[INFO]: The ROS shell environment setup is skipped during the host setup' >&2
    else
      
      # TASK [Determine the ROS shell setup script filepath]
      
      ROS_CODENAME="$(yq -r .ros.version_codename "${JUGGLEBOT_RC_FILEPATH}")"
      ROS_SETUP_FILEPATH="/opt/ros/${ROS_CODENAME}/setup.zsh"
      
      if [[ -f "${ROS_SETUP_FILEPATH}" ]]; then
        
        # TASK [Enable ROS by sourcing its setup script into the shell environment]
        
        source "${ROS_SETUP_FILEPATH}"
        
        # TASK [Specify the ROS domain id, which controls the discoverability of nodes]

        export ROS_DOMAIN_ID="$(yq -r .ros.domain_id "${JUGGLEBOT_RC_FILEPATH}")"
        
      else
        echo '[WARNING]: The ROS shell setup script was not found.' >&2
      fi
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
    echo -e "\n[ERROR]: Unrecognized event type (${EVENT_TYPE})." >&2
    exit 2
    ;;
esac

