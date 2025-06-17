#
# TMUX Configuration
#

# Auto-start TMUX session if not already in one and not in SSH
if [ -z "$TMUX" ] && [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    # Check if TMUX is installed
    if command -v tmux >/dev/null 2>&1; then
        # Create or attach to a session called "main"
        tmux attach -t main || tmux new -s main
    fi
fi

# Aliases for TMUX
alias tn="tmux new -s"                   # Create new named session: tn myproject
alias ta="tmux attach -t"                # Attach to session: ta myproject
alias tl="tmux list-sessions"            # List all sessions
alias tk="tmux kill-session -t"          # Kill session: tk myproject
alias ts="tmux switch -t"                # Switch between sessions
alias tks="tmux kill-server"             # Kill all sessions

# Create a new TMUX session with a specific layout for development
tmux_dev() {
    local SESSION=$1
    if [ -z "$SESSION" ]; then
        SESSION="dev"
    fi
    
    # Check if session already exists
    tmux has-session -t $SESSION 2>/dev/null
    if [ $? != 0 ]; then
        # Create a new session with a window for code editing
        tmux new-session -d -s $SESSION -n "code"
        
        # Create a window for running commands
        tmux new-window -t $SESSION:1 -n "run"
        
        # Create a window for monitoring
        tmux new-window -t $SESSION:2 -n "monitor"
        tmux send-keys -t $SESSION:2 "htop" C-m
        
        # Return to the first window
        tmux select-window -t $SESSION:0
    fi
    
    # Attach to the session
    tmux attach-session -t $SESSION
}

# For sending the same command to all panes in a window
tmux_broadcast() {
    if [ -z "$TMUX" ]; then
        echo "Not in a TMUX session"
        return 1
    fi
    
    local state=$(tmux show-window-options synchronize-panes | cut -d ' ' -f 2)
    
    if [ "$state" = "on" ]; then
        tmux set-window-option synchronize-panes off
        echo "Broadcast mode disabled"
    else
        tmux set-window-option synchronize-panes on
        echo "Broadcast mode enabled - commands will be sent to all panes"
    fi
}
alias tb="tmux_broadcast"  # Toggle broadcast mode
