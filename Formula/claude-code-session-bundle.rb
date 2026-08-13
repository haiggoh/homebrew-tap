require "json"

class ClaudeCodeSessionBundle < Formula
  desc "Compact Claude Code transcripts for review and LLM context handoff"
  homepage "https://github.com/haiggoh/claude-code-session-bundle"
  url "https://github.com/haiggoh/claude-code-session-bundle/releases/download/v0.6.2/claude-code-session-bundle-0.6.2.tar.gz"
  sha256 "b7c80b090b1eb7b3d74ac1f1b02e96be0bd90e02f79c68189068a7d26be340e8"
  license "MIT"

  depends_on "python@3.14"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"compact_session_bundle.py" => "cc-transcript"
  end

  test do
    # Derived from the url's version rather than restated: a literal here has to be
    # bumped in lockstep with the url, and when it isn't the test either fails for the
    # wrong reason or (as happened at 0.5.0, where both were stale) passes against a
    # superseded release.
    assert_equal "#{version}\n", shell_output("#{bin}/cc-transcript --version")

    cp libexec/"compact_session_bundle.py", testpath
    system formula_opt_bin("python@3.14")/"python3",
           "-m", "py_compile",
           testpath/"compact_session_bundle.py"

    input = testpath/"session.jsonl"
    output = testpath/"out"
    record = {
      type:      "user",
      sessionId: "session",
      message:   {
        role:    "user",
        content: [
          {
            type:   "image",
            source: {
              type:       "base64",
              media_type: "image/png",
              data:       "cmF3",
            },
          },
        ],
      },
    }
    input.write("#{JSON.generate(record)}\n")

    system bin/"cc-transcript", input, "-o", output

    assert_equal [
      "session.compact.jsonl.txt",
      "session.indexed_capsule.md",
    ], output.children.map { |child| child.basename.to_s }.sort

    compact = output/"session.compact.jsonl.txt"
    indexed = output/"session.indexed_capsule.md"
    records = compact.readlines(chomp: true).map { |line| JSON.parse(line) }
    header = records.first.fetch("__compact_session_header__")
    binary = records[1].fetch("message").fetch("content").first
                       .fetch("source").fetch("data")

    assert_equal 3, header.fetch("__bundle_format__")
    assert header.fetch("__omission_policy__").fetch("base64_omitted")
    assert binary.key?("__omitted_binary__")
    assert_operator indexed.size, :>, 0
  end
end
