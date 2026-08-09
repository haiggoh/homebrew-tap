class ClaudeCodeSessionBundle < Formula
  desc "Compact Claude Code transcripts for review and LLM context handoff"
  homepage "https://github.com/haiggoh/claude-code-session-bundle"
  url "https://github.com/haiggoh/claude-code-session-bundle/releases/download/v0.5.0/claude-code-session-bundle-0.5.0.tar.gz"
  sha256 "1cd0500bd9e728d1ff281e1bc5f900927423be260be869076ca4adcc7763e682"
  license "MIT"

  depends_on "python@3.14"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"compact_session_bundle.py" => "cc-transcript"
  end

  test do
    assert_match "0.5.0", shell_output("#{bin}/cc-transcript --version")

    cp libexec/"compact_session_bundle.py", testpath
    cp_r libexec/"tests", testpath/"tests"

    system formula_opt_bin("python@3.14")/"python3",
           "-m", "py_compile",
           testpath/"compact_session_bundle.py"

    system formula_opt_bin("python@3.14")/"python3",
           "-m", "unittest", "discover",
           "-s", testpath/"tests",
           "-v"
  end
end
