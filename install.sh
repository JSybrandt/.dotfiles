#!/bin/bash
# This function installs my setup on a debian-based system.

################################################################################
# Helpers ######################################################################
################################################################################

# Writes arguments to stderr.
log_fatal(){
  echo "ERR: $@" 1>&2
  exit 1
}

# Exits if this file isn't run as root.
assert_sudo(){
  if [[ $(id -u) -ne 0 ]]; then
    log_fatal "Must run as root."
  fi
}

# Exits if the last command did not complete successfully.
assert_success(){
  if [[ $? -ne 0 ]]; then
    log_fatal "Unexpected error in subprocess. Code: $?"
  fi
}

# Exits if $1 isn't in the current path.
assert_in_path(){
  builtin type -P "$1" &> /dev/null
  if [[ $? -ne 0 ]]; then
    log_fatal "$1 not in path."
  fi
}

# Exits if $1 isn't a file.
assert_file(){
  if [[ ! -f "$1" ]]; then
    log_fatal "$1 is not a file."
  fi
}

# Exits if $1 isn't a dir.
assert_dir(){
  if [[ ! -d "$1" ]]; then
    log_fatal "$1 is not a dir."
  fi
}

# Runs apt install if $1 is not installed.
assert_in_path apt
assert_in_path dpkg-query
assert_in_path grep
install_if_missing(){
  PKG=$1
  # Returns 0 if the package is missing
  MISSING=$(dpkg-query -W -f='${Status}' "$PKG" 2>/dev/null |
            grep -c "ok installed")
  if [[ $MISSING -eq 0 ]]; then
    echo "Installing $PKG."
    apt install -y "$PKG" &> /dev/null
    assert_success
  fi
}

# If $2 does not exist, create a simlink from $2 -> $1.
link_if_missing(){
  SOURCE=$1
  DEST=$2
  if [[ ! -e $SOURCE ]]; then
    log_fatal "Cannot simlink non-existing path $SOURCE."
  fi
  if [[ ! -e $DEST ]]; then
    echo "Creating simlink: $DEST -> $SOURCE."
    ln -sf $SOURCE $DEST
  fi
}

# If $1 doesn't exist, mkdir -p as $USER_NAME
mkdir_if_missing(){
  DIR=$1
  if [[ ! -d $DIR ]]; then
    echo "Creating $DIR"
    sudo -u $USER_NAME mkdir -p $DIR
  fi
}

# If $1 is not found in $2, append $1 to #2.
add_command_to_file(){
  COMMAND=$1
  FILE=$2
  if [[ ! -f $FILE ]]; then
    echo "Creating $FILE."
    touch $FILE
  fi
  # If the command is not present in profile.
  if ! grep -q "$COMMAND" $FILE; then
    echo "Adding '$COMMAND' to $FILE."
    echo "" >> $FILE
    echo $COMMAND >> $FILE
  fi
}

################################################################################
# Config #######################################################################
################################################################################

assert_sudo

USER_NAME="jsybrandt"
USER_HOME=$(getent passwd $USER_NAME | cut -d: -f6)
assert_success
assert_dir $USER_HOME

DOT_DIR="$USER_HOME/.dotfiles"
CONF_DIR="$DOT_DIR/conf"
BIN_DIR="$DOT_DIR/bin"
if [[ ! -d $DOT_DIR ]]; then
  echo "Installing dotfiles."
  sudo -u $USER_NAME git clone --depth=1 \
    https://github.com/JSybrandt/.dotfiles.git $DOT_DIR &> /dev/null
  assert_success
fi
assert_dir $DOT_DIR
assert_dir $CONF_DIR
assert_dir $BIN_DIR

################################################################################
# Packages #####################################################################
################################################################################

install_if_missing build-essential
install_if_missing curl
install_if_missing fonts-powerline
install_if_missing git
install_if_missing gnome-tweaks
install_if_missing htop
install_if_missing python3
install_if_missing python3-pip
install_if_missing tmux
install_if_missing vim-gtk
install_if_missing zsh

################################################################################
# Make CAPSLOCK an extra Esc ###################################################
################################################################################

# These files _sometimes_ work
XKBMAP_COMMAND="setxkbmap -option caps:escape"
add_command_to_file "$XKBMAP_COMMAND" $USER_HOME/.profile
add_command_to_file "$XKBMAP_COMMAND" $USER_HOME/.xinitrc
add_command_to_file "$XKBMAP_COMMAND" $USER_HOME/.Xresources
# On Pop_OS, the autostart desktop file is what gets it.

AUTOSTART_DIR=$USER_HOME/.config/autostart
mkdir_if_missing $AUTOSTART_DIR
sudo -u $USER_NAME cp -f $CONF_DIR/caps_to_esc_autostart $AUTOSTART_DIR/caps_to_esc.desktop
assert_success
sudo -u $USER_NAME chmod +x $AUTOSTART_DIR/caps_to_esc.desktop
assert_success


################################################################################
# ZSH Config ###################################################################
################################################################################

# Change default shell to ZSH
assert_in_path zsh
ZSH_PATH=$(which zsh)
CURRENT_SHELL=$(getent passwd $USER_NAME | cut -d: -f7)
if [[ $CURRENT_SHELL != $ZSH_PATH ]]; then
  echo "Setting $ZSH_PATH as default shell."
  chsh -s $(which zsh) $USER_NAME
  assert_success
fi
link_if_missing $CONF_DIR/zsh $USER_HOME/.zshrc

# Set marks dir for m and j commands.
mkdir_if_missing $USER_HOME/.marks

# Install oh my zsh (exported env vars defined by Oh-My-Zsh api).
export CHSH="no"
export RUNZSH="no"
export KEEP_ZSHRC="yes"
export ZSH=$USER_HOME/.oh-my-zsh
if [[ ! -d $ZSH ]]; then
  echo "Installing Oh-My-Zsh."
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  assert_success
fi

# Install Powerlevel10k Theme
THEME_DIR=$ZSH/themes/powerlevel10k
if [[ ! -d "$THEME_DIR" ]]; then
  echo "Installing Powerlevel10k."
  sudo -u $USER_NAME git clone --depth=1 \
    https://github.com/romkatv/powerlevel10k.git $THEME_DIR &> /dev/null
  assert_success
fi

link_if_missing $CONF_DIR/zsh_theme $USER_HOME/.p10k.zsh

################################################################################
# Configure Vim ################################################################
################################################################################

link_if_missing $CONF_DIR/vim $USER_HOME/.vimrc
# Install plugged
PLUG_INSTALL_FILE=$USER_HOME/.vim/autoload/plug.vim
if [[ ! -f $PLUG_INSTALL_FILE ]]; then
  echo "Installing vim-plug."
  sudo -u $USER_NAME curl -sfLo $PLUG_INSTALL_FILE --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  # Install plugins
  sudo -u $USER_NAME vim +PlugInstall +qall
  assert_success
fi

################################################################################
# Configure Tmux ###############################################################
################################################################################

TMUX_DOTFILE="$CONF_DIR/tmux"
assert_file $TMUX_DOTFILE
if [[ ! -d "$USER_HOME/.tmux" ]]; then
  echo "Installing Oh-My-Tmux."
  sudo -u $USER_NAME \
    git clone --depth=1 https://github.com/gpakosz/.tmux.git \
    $USER_HOME/.tmux
  assert_success
fi
link_if_missing $USER_HOME/.tmux/.tmux.conf $USER_HOME/.tmux.conf
link_if_missing $TMUX_DOTFILE $USER_HOME/.tmux.conf.local

################################################################################
# Misc Simlinks ################################################################
################################################################################

link_if_missing $BIN_DIR $USER_HOME/.bin
link_if_missing $CONF_DIR/latexmk $USER_HOME/.latexmkrc
