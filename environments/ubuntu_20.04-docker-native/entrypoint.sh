#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
IFS=$'\t\n' # For predictability
rc=0

# TASK [Define variables]

INIT_FLAG_FILEPATH="${HOME}/.user-dir-initialized"

# TASK [Start dbus-daemon]

sudo /usr/bin/dbus-daemon --system &

# TASK [Start sshd]

sudo /usr/sbin/sshd -D &

# TASK [Determine whether the user's nome directory needs to be initialized]

if [[ ! -f "${INIT_FLAG_FILEPATH}" ]]; then

  # TASK [Initializes the user's home directory in the /home volume`]

  rm -rf "${HOME}"
  mv "/entrypoint/${USER}" "${HOME}"

  # TASK [Symlink the ~/.oh-my-zsh/custom directory to the mounted custom directory]
  
  if [[ -d /entrypoint/oh-my-zsh-custom ]]; then
    rm -rf "${HOME}/.oh-my-zsh/custom"
    ln -s -T /entrypoint/oh-my-zsh-custom "${HOME}/.oh-my-zsh/custom"
  fi

  # TASK [Signal that initialization is complete]
  # 
  # Note: External scripts poll for the existence of this flag file when
  # waiting for initialization.
  
  touch "${INIT_FLAG_FILEPATH}"
fi

# TASK [Exec the CMD or the specified command]

exec "$@"

