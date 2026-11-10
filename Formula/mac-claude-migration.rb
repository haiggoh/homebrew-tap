class MacClaudeMigration < Formula
  desc "Back up a Claude Code setup and restore it on a new Mac"
  homepage "https://github.com/haiggoh/mac-claude-migration"
  # Tag source archive (not a release asset) so the tap's hourly bump-formulas
  # workflow repoints this url+sha256 at each new release automatically.
  url "https://github.com/haiggoh/mac-claude-migration/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "4748eae59902a10bd334c0a74203165826770711eb35ed97c07982f4fed33627"
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
    require "tmpdir"
    require "shellwords"

    assert_predicate bin/"mac-claude-backup", :executable?
    assert_predicate bin/"mac-claude-restore", :executable?
    assert_equal version.to_s, (libexec/"VERSION").read.strip
    # Exact first usage lines, copied from `./backup.sh --help` / `./restore.sh --help`
    # in the mac-claude-migration checkout (2026-11-08) — not restated from memory.
    assert_equal "📦 backup.sh — capture the NON-redownloadable state of this Claude Code setup.\n",
                 shell_output("#{bin}/mac-claude-backup --help").lines.first
    assert_equal "📦 restore.sh — rebuild the Claude Code setup on the NEW Mac from an archive\n",
                 shell_output("#{bin}/mac-claude-restore --help").lines.first

    # The url must stay in the form the tap's hourly bump-formulas workflow recognises
    # (ARCHIVE_URL_RE in .github/scripts/bump_formulas.py): any other downloadable
    # tarball installs fine but silently stops future releases reaching `brew upgrade`.
    url_re = %r{\Ahttps://github\.com/[^/]+/[^/]+/archive/refs/tags/v[0-9][0-9A-Za-z.-]*\.tar\.gz\z}
    assert_match url_re, self.class.url

    # Run the REAL installed command from its install location with an empty HOME:
    # backup.sh resolves its sibling VERSION from its own path, so the archive must
    # carry TOOL_VERSION=<release version>, not "dev". This goes RED if a wrapper
    # execs a copy outside libexec (e.g. in bin/) or is a stub that never runs it.
    fake_home = Dir.mktmpdir
    out = Dir.mktmpdir
    old_home = Dir.home
    ENV["HOME"] = fake_home
    begin
      ran = system "#{bin}/mac-claude-backup", out
    ensure
      ENV["HOME"] = old_home
    end
    assert ran, "mac-claude-backup exited non-zero"
    archive = Dir[File.join(out, "claude-migration-*.tar.gz")].first
    assert archive, "mac-claude-backup wrote no archive"
    meta = `tar xzf #{Shellwords.escape(archive)} -O meta.env 2>/dev/null`
    assert_includes meta, "TOOL_VERSION=#{version}"
  end
end
