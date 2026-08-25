class HumanShell < Formula
  desc "Make zsh command outcomes visible in macOS Terminal"
  homepage "https://github.com/haiggoh/human-shell"
  url "https://github.com/haiggoh/human-shell/releases/download/v1.3.0/human-shell-1.3.0.tar.gz"
  sha256 "ee03e659204ed27ba3c140ad1ec3d275b0048d0d9c9b9bc6af0564742df3e58d"
  license "MIT"
  revision 2

  depends_on "dockutil"
  depends_on :macos

  def install
    libexec.install Dir["*"]

    (bin/"human-shell-install").write <<~EOS
      #!/bin/zsh
      set -e
      source_dir="#{libexec}"
      root="$HOME/.local/share/human-shell"
      destination="$root/current"
      staging="$root/.staging-$$"
      backup="$root/.previous-$(date '+%Y%m%d-%H%M%S')"

      mkdir -p "$root"
      rm -rf "$staging"
      cp -R "$source_dir" "$staging"

      if [[ -e "$destination" ]]; then
        mv "$destination" "$backup"
        print "PASS: previous user installation backed up to:"
        print "  $backup"
      fi

      mv "$staging" "$destination"
      chmod 755 "$destination/install.sh" "$destination/uninstall.sh"

      if "$destination/install.sh" "$@"; then
        print "PASS: Human Shell #{version} installed for this user."
        print 'Run: source "$HOME/.zshrc"'

        # The backup above exists so a failed install can be rolled back. Once
        # the install has succeeded it is only history, and one is left per run,
        # so without this the directory grows by a copy on every upgrade and
        # nothing ever removes it. Keep the newest few and drop the rest.
        keep="${HUMAN_SHELL_KEEP_PREVIOUS:-3}"
        previous=("$root"/.previous-*(N/om))
        if (( ${#previous} > keep )); then
          for stale in "${previous[@]:$keep}"; do
            rm -rf "$stale"
          done
          pruned=$(( ${#previous} - keep ))
          print "PASS: pruned $pruned superseded user $( (( pruned == 1 )) && print copy || print copies ), kept the newest $keep."
        fi
      else
        exit_status=$?
        print -u2 "FAIL: user installer exited with status $exit_status."
        rm -rf "$destination"
        if [[ -e "$backup" ]]; then
          mv "$backup" "$destination"
          print -u2 "Restored the previous user installation."
        fi
        exit "$exit_status"
      fi
    EOS

    (bin/"human-shell-uninstall").write <<~EOS
      #!/bin/zsh
      set -e
      installation="$HOME/.local/share/human-shell/current"

      if [[ -x "$installation/uninstall.sh" ]]; then
        "$installation/uninstall.sh"
      else
        print "INFO: no active Human Shell user installation was found."
      fi

      print "INFO: Homebrew package files remain installed."
      print "Remove them separately with: brew uninstall human-shell"
    EOS
  end

  def caveats
    <<~EOS
      Complete the per-user setup with:

        human-shell-install
        source ~/.zshrc

      This generates both Dock launchers locally, applies this Mac's Terminal icon,
      and adds both launchers to the Dock. To skip Dock changes, run:

        human-shell-install --no-dock

      Homebrew does not modify your shell configuration or Dock during brew install.
      After a future brew upgrade, rerun human-shell-install to refresh the user copy.

      Each run keeps the previous user copy under
      ~/.local/share/human-shell/.previous-<timestamp> so a failed install can be
      rolled back. The newest 3 are kept and older ones are pruned; set
      HUMAN_SHELL_KEEP_PREVIOUS to change how many are retained.
    EOS
  end

  test do
    assert_predicate bin/"human-shell-install", :executable?
    assert_predicate bin/"human-shell-uninstall", :executable?
    assert_path_exists libexec/"human-shell.zsh"
    assert_path_exists libexec/"Human Shell.applescript"
    assert_path_exists libexec/"Human Shell Failures Only.applescript"
    assert_path_exists libexec/"scripts/scrub-launcher-history.zsh"

    # The shipped suite checks the exit-status-to-label table, the status-1
    # findings table, the right-aligned report line, the one-label-per-command
    # rule, the history filter and scrubber, and the syntax of every script and
    # applet. It needs no terminal and writes only inside its own temporary
    # directories.
    system "/bin/zsh", libexec/"tests/run-tests.zsh"
  end
end
