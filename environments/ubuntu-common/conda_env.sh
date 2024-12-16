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

case "${EVENT_TYPE}" in
  activate)
    
    # TASK [Activate]
    
    export JUGGLEBOT_REPO_DIR="${HOME}/Jugglebot"
    export JUGGLEBOT_CONFIG_DIR="${HOME}/.jugglebot"
    ;;
  
  deactivate)
  
    # TASK [Deactivate]

    unset JUGGLEBOT_REPO_DIR
    unset JUGGLEBOT_CONFIG_DIR
    ;;

  *)
    echo -e "\n[ERROR]: Unrecognized event type (${EVENT_TYPE})."
    exit 2
    ;;
esac

