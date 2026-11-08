class MacClaudeMigration < Formula
  desc "Back up a Claude Code setup and restore it on a new Mac"
  homepage "https://github.com/haiggoh/mac-claude-migration"
  # Tag source archive (not a release asset) so the tap's hourly bump-formulas
  # workflow repoints this url+sha256 at each new release automatically.
  url "https://github.com/haiggoh/mac-claude-migration/archive/refs/tags/v0.1.4.tar.gz"
  sha256 "442a9dac4b2fa00d1a83bfc6c7e075d2341ec4eac6253578bad87e4386c9d70f"
  license "MIT"

  depends_on :macos

  def install
    libexec.install Dir["*"]
    # backup.sh resolves its sibling VERSION from its own $0 path, so the wrappers
    # must exec the libexec copies (argv[0] = libexec/backup.sh), never a copy in bin/.
    (bin/"mac-claude-backup").write <<~EOS
      #!/bin/sh
      exec "#{libexec}/backup.sh" "$@"
    EOS
    (bin/"mac-claude-restore").write <<~EOS
      #!/bin/sh
      exec "#{libexec}/restore.sh" "$@"
    EOS
  end

  test do
    assert_predicate bin/"mac-claude-backup", :executable?
    assert_predicate bin/"mac-claude-restore", :executable?
    assert_equal version.to_s, (libexec/"VERSION").read.strip
    # Exact first usage lines, copied from `./backup.sh --help` / `./restore.sh --help`
    # in the mac-claude-migration checkout (2026-11-08) — not restated from memory.
    assert_equal "📦 backup.sh — capture the NON-redownloadable state of this Claude Code setup.\n",
                 shell_output("#{bin}/mac-claude-backup --help").lines.first
    assert_equal "📦 restore.sh — rebuild the Claude Code setup on the NEW Mac from an archive\n",
                 shell_output("#{bin}/mac-claude-restore --help").lines.first
  end
end
