# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin/google-cloud-sdk/bin:$HOME/bin:/usr/local/bin:$PATH:/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/go/bin:/opt/local/bin:$HOME/.local/bin:$HOME/.cargo/bin

# You may need to manually set your language environment
export LANG=en_US.UTF-8

## Automatic load of Python venvs if existing
## from stackoverflow: https://stackoverflow.com/questions/45216663/how-to-automatically-activate-virtualenvs-when-cding-into-a-directory
## venv activation kills the starship prompt so a starhip init is needed to get it back
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
# Setup Direnv

eval "$(direnv hook zsh)"

eval "$(starship init zsh)"

eval "$(zoxide init zsh)"

#export GITLAB_ACCESS_TOKEN=`security find-generic-password -w -s "Gitlab APL" -a "token"`
#export GITLAB_TOKEN=`security find-generic-password -w -s "Gitlab APL" -a "token"`
#export MSTEAMS_WEBHOOK=`security find-generic-password -w -s "Gafka Test Teams Webhook" -a "teams"`
#export AIVENM3_USER=XXXX
#export AIVENM3_PW=XXXX
#export ENTRAID_APPLICATIONID=`security find-generic-password -w -s "EntraID - ApplicationID" -a "gentra"`
#export ENTRAID_TENANTID=`security find-generic-password -w -s "EntraID - TenantID" -a "gentra"`
#export ENTRAID_SECRETID=`security find-generic-password -w -s "EntraID - SecretID" -a "gentra"`
#export ENTRAID_SECRET=`security find-generic-password -w -s "EntraID - Secret" -a "gentra"`
#export GEMINI_API_KEY=`security find-generic-password -w -s "gemini" -a "astronvim"` 
#export TOGGL_API_TOKEN=`security find-generic-password -w -s "toggl" -a "api"` 

bindkey -v

ssh-add --apple-load-keychain -q

# Load completions from all completion directories under ~/.zsh/completions.
# Glob qualifiers dereference symlinks (`-`): these directories are assembled
# from several repositories, so every entry in them is a symlink. A plain
# `(.N)`/`(N/)` matches only real files/dirs and would silently load nothing.
for completion_dir in ~/.zsh/completions(-/N) ~/.zsh/completions/*(-/N); do
  fpath=("$completion_dir" $fpath)
done
autoload -Uz compinit
compinit

# Load all rc snippets.
for rc_file in ~/.zsh/rcs/*(-.N); do
  source "$rc_file"
done

# Load all aliases.
for alias_file in ~/.zsh/aliases/*(-.N); do
  source "$alias_file"
done

# Load all custom functions.
for fn_file in ~/.zsh/functions/*(-.N); do
  source "$fn_file"
done
