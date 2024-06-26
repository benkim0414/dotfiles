function initialize_pyenv_virtualenv() {
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
}

async_start_worker pyenv_worker -n
async_register_callback pyenv_worker initialize_pyenv_virtualenv
async_job pyenv_worker sleep 0.1

