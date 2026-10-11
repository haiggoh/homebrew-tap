# haiggoh Homebrew Tap

Homebrew formulae for projects published by [haiggoh](https://github.com/haiggoh).

## free-agents

```zsh
brew install haiggoh/tap/free-agents
free-agents-install        # registers the plugin with Claude Code (uses `claude plugin install`)
csl setup-remote           # optional: add free-tier API keys
csl                        # session picker
```

Puts `csl`, `lowkey` and `lk` on your PATH. They run the newest free-agents version Claude Code
has installed for you, so the command line and the plugin stay on the same release. Local MLX
inference and model downloads are optional and are not installed by the formula; see the
[free-agents README](https://github.com/haiggoh/free-agents#readme).

After upgrading: `brew upgrade free-agents && claude plugin update free-agents@haiggoh`.

## Human Shell

```zsh
brew install haiggoh/tap/human-shell
human-shell-install
source ~/.zshrc
```

The formula installs versioned package files through Homebrew. The explicit setup command copies the current version to `~/.local/share/human-shell/current`, updates `.zshrc` with a bounded managed block, and generates both Dock launchers locally with the Mac's own Terminal icon.

After upgrading:

```zsh
brew upgrade human-shell
human-shell-install
source ~/.zshrc
```

Remove the user integration first, then the formula:

```zsh
human-shell-uninstall
source ~/.zshrc
brew uninstall human-shell
```
