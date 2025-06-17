_ENV_PROJECT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))

source ${_ENV_PROJECT_DIR}/.bashrc.basic_funcs

create_softlink ${_ENV_PROJECT_DIR}/.bashrc.user ~/.bashrc.${USER}

# check if git config exist 
if [ ! -f ~/.gitconfig ]; then
  echo_info "Creating git config file"
  cp ${_ENV_PROJECT_DIR}/.gitconfig ~/.gitconfig
fi

# Source TMUX configuration
echo_info "Setting up TMUX configuration"
if [ -f ${_ENV_PROJECT_DIR}/.bashrc.tmux ]; then
  source ${_ENV_PROJECT_DIR}/.bashrc.tmux
  echo_success "TMUX configuration loaded"
else
  echo_warning "TMUX configuration file not found"
fi
