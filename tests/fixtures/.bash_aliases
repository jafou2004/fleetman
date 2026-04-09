# ### Git
alias gs='git status' # Show working tree status
alias gl='git log --oneline -10'
alias gd='git diff'

# ### Docker
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}"' # List running containers
alias dlog='docker logs -f'

# ### Scripts
alias fl='fleetman' # Fleetman shorthand
alias fls='fleetman sync'
