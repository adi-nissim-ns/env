_ENV_PROJECT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))

source ${_ENV_PROJECT_DIR}/.bashrc.basic_funcs

create_softlink ${_ENV_PROJECT_DIR}/.bashrc.user ~/.bashrc.${USER}

# checl if git config exist 
if [ ! -f ~/.gitconfig ]; then
  echo_info "Creating git config file"
  cp ${_ENV_PROJECT_DIR}/.gitconfig ~/.gitconfig
fi