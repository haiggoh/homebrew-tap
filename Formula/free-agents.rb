class FreeAgents < Formula
  desc "Run Claude Code on free inference: local MLX models and free cloud APIs"
  homepage "https://github.com/haiggoh/free-agents"
  url "https://github.com/haiggoh/free-agents/releases/download/v0.39.0/free-agents-0.39.0.tar.gz"
  sha256 "9190ebcb0ce3acc1d0a1df6926d30f00b18e18f3ec785c5c2eb2f76187978366"
  license "MIT"

  # csl and the launchers need bash 4+ (associative arrays); macOS ships bash 3.2.
  depends_on "bash"
  depends_on "python@3.14"

  def install
    libexec.install Dir["*"], ".claude-plugin"

    # PATH commands run the NEWEST free-agents Claude Code has installed for this user, so `csl`
    # and the plugin inside Claude Code are the same release. Before the plugin is installed they
    # fall back to the copy Homebrew shipped. FREE_AGENTS_ROOT overrides both.
    plugin_cache = "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/haiggoh/free-agents"
    (libexec/"brew-resolve.sh").write <<~EOS
      #!/bin/bash
      # Resolve the free-agents root: FREE_AGENTS_ROOT, else the newest Claude Code plugin copy,
      # else this Homebrew copy. Read-only: never writes the plugin store.
      fa_root() {
        if [ -n "${FREE_AGENTS_ROOT:-}" ]; then
          [ -f "$FREE_AGENTS_ROOT/.claude-plugin/plugin.json" ] || {
            echo "free-agents: FREE_AGENTS_ROOT is not a free-agents checkout: $FREE_AGENTS_ROOT" >&2
            return 1
          }
          printf '%s' "$FREE_AGENTS_ROOT"
          return 0
        fi
        local cache="#{plugin_cache}" newest
        if [ -d "$cache" ]; then
          newest=$(ls -1 "$cache" 2>/dev/null | grep -E '^[0-9]+[.][0-9]+[.][0-9]+$' |
                   sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
          if [ -n "$newest" ] && [ -f "$cache/$newest/.claude-plugin/plugin.json" ]; then
            printf '%s' "$cache/$newest"
            return 0
          fi
        fi
        printf '%s' "#{opt_libexec}"
      }
    EOS

    { "csl" => "bin/csl", "lowkey" => "bin/lowkey", "lk" => "bin/lowkey" }.each do |name, rel|
      (bin/name).write <<~EOS
        #!/bin/bash
        . "#{opt_libexec}/brew-resolve.sh"
        root=$(fa_root) || exit 1
        PATH="#{formula_opt_bin("bash")}:#{formula_opt_bin("python@3.14")}:$PATH" exec "$root/#{rel}" "$@"
      EOS
    end

    (bin/"free-agents-install").write <<~EOS
      #!/bin/bash
      # free-agents-install — register the free-agents plugin with Claude Code for this user.
      # Uses Claude Code's own CLI (never edits its plugin registry by hand). Local inference
      # (Rapid-MLX / CUDA) and model downloads are NOT installed here: remote free-API sessions
      # need neither.
      # Usage: free-agents-install [--help]
      set -euo pipefail
      case "${1:-}" in
        "") ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \\{0,1\\}//'; exit 0 ;;
        *) echo "usage: free-agents-install [--help]" >&2; exit 2 ;;
      esac
      command -v claude >/dev/null 2>&1 || {
        echo "FAIL: the claude CLI is not on PATH. Install Claude Code first." >&2
        exit 1
      }
      claude plugin marketplace add haiggoh/get-haiggoh >/dev/null 2>&1 ||
        claude plugin marketplace update haiggoh >/dev/null 2>&1 || true
      if claude plugin install free-agents@haiggoh --scope user; then
        echo "PASS: free-agents is installed in Claude Code (restart it, or run /reload-plugins)."
      else
        echo "FAIL: 'claude plugin install free-agents@haiggoh' did not succeed." >&2
        echo "      Inside Claude Code you can run:  /plugin marketplace add haiggoh/get-haiggoh" >&2
        exit 1
      fi
      echo
      echo "Next:"
      echo "  csl setup-remote   add free-tier API keys (one file per provider in ~/.api_keys)"
      echo "  csl                open the session picker"
      echo "  Local MLX inference is optional: see the README section on local backends."
    EOS
  end

  def caveats
    <<~EOS
      Register the plugin with Claude Code (once per user):

        free-agents-install

      Homebrew does not touch Claude Code during brew install. `csl`, `lowkey` and `lk` run the
      newest free-agents Claude Code has installed (set FREE_AGENTS_ROOT to point them elsewhere).
      After `brew upgrade free-agents`, update the plugin as well:

        claude plugin update free-agents@haiggoh

      A command of the same name earlier on your PATH (for example ~/.local/bin/csl) still wins.
    EOS
  end

  test do
    assert_predicate bin/"free-agents-install", :executable?
    assert_match "usage", shell_output("#{bin}/free-agents-install --help").downcase
    assert_path_exists libexec/".claude-plugin/plugin.json"
    assert_equal version.to_s, (libexec/"VERSION").read.strip
    ENV["FREE_AGENTS_ROOT"] = libexec.to_s
    assert_match "csl", shell_output("#{bin}/csl --help 2>&1")
  end
end
