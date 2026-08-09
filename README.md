# haiggoh Homebrew Tap

Homebrew formulae for projects published by [haiggoh](https://github.com/haiggoh).

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
