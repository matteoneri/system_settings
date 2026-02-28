# Running Claude Code with multiple accounts

Claude Code stores its configuration (account credentials, settings, theme) in a single directory. By default this is `~/.claude`. To use multiple accounts you create separate config directories and a shell function that picks the right one.

## Setup

### 1. Create config directories

```bash
mkdir -p ~/.claude-personal ~/.claude-work
```

### 2. Authenticate each account

```bash
# Log in with your personal account
CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude

# Log in with your work account
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude
```

Each command will open the browser for authentication. After logging in, that account's credentials are stored in the corresponding directory.

### 3. Add the account picker to your shell

Add this to your `~/.zshrc` (or `~/.bashrc` if you use bash — replace `read -r -k 1` with `read -r -n 1`):

```zsh
claude() {
    echo "Account: [1] Work (default)  [2] Personal"
    read -r -k 1 "choice?"
    [[ "$choice" != $'\n' ]] && echo
    if [[ "$choice" == "2" ]]; then
        CLAUDE_CONFIG_DIR="$HOME/.claude-personal" command claude "$@"
    else
        CLAUDE_CONFIG_DIR="$HOME/.claude-work" command claude "$@"
    fi
}
```

Then reload your shell:

```bash
source ~/.zshrc
```

### 4. Use it

```bash
claude          # prompts you to pick an account
claude -p "hi"  # same picker, then runs with the chosen account
```

## Notes

- Each config directory is fully independent: separate credentials, settings, history, and theme.
- You can set a different theme per account to visually distinguish them (e.g. dark for personal, light for work).
- The `command` keyword in the function bypasses the function itself and calls the real `claude` binary, avoiding infinite recursion.
- To skip the prompt and force an account: `CLAUDE_CONFIG_DIR="$HOME/.claude-work" command claude`
