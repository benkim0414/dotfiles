function initialize_pyenv() {
  eval "$(pyenv init -)"
}

function initialize_pyenv_virtualenv() {
  eval "$(pyenv virtualenv-init -)"
}

async_start_worker pyenv_worker -n
async_register_callback pyenv_worker initialize_pyenv_virtualenv
async_job pyenv_worker initialize_pyenv

