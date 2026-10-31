# 🚰 haiggoh Homebrew Tap

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

## Claude Code Transcript Distiller

```zsh
brew install haiggoh/tap/claude-code-transcript-distiller
cc-transcript session.jsonl -o out/
```

Puts `cc-transcript` on your PATH. It distills a Claude Code session transcript into a
compact evidence bundle (`<session>.compact.jsonl.txt`) and an indexed handoff capsule
(`<session>.indexed_capsule.md`), with base64 blobs omitted rather than carried. The
pre-rename entry point `compact_session_bundle.py` stays valid inside the package, so
scripts written against 0.6.x keep working. Python comes from the formula (python@3.14);
see the [project README](https://github.com/haiggoh/Claude-Code-Transcript-Distiller#readme).

After upgrading: `brew upgrade claude-code-transcript-distiller`.

## Automatic formula updates

`.github/workflows/bump-formulas.yml` checks every hour whether a formula's repo has a newer
GitHub release, and if so points the formula at the new release tarball (url + sha256, the hash
computed from the downloaded file) and commits it. A release therefore reaches `brew upgrade`
within the hour with no manual step. Run it right away with
`gh workflow run bump-formulas.yml -R haiggoh/homebrew-tap` (optionally `-f formula=free-agents`).
The logic is `.github/scripts/bump_formulas.py` (`--help`, `--dry-run`); its offline tests run first.
