function load_nvm() {
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

function source_bash_completion() {
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

async_start_worker nvm_worker -n
async_register_callback nvm_worker source_bash_completion
async_job nvm_worker load_nvm

