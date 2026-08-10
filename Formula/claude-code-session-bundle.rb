require "json"

class ClaudeCodeSessionBundle < Formula
  desc "Compact Claude Code transcripts for review and LLM context handoff"
  homepage "https://github.com/haiggoh/claude-code-session-bundle"
  url "https://github.com/haiggoh/claude-code-session-bundle/releases/download/v0.6.1/claude-code-session-bundle-0.6.1.tar.gz"
  sha256 "305ac1fe3ed5d0b0fbb578fd4735623a7301da55aee99963d0ea78055c8c641f"
  license "MIT"

  depends_on "python@3.14"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"compact_session_bundle.py" => "cc-transcript"
  end

  test do
    assert_equal "0.6.1\n", shell_output("#{bin}/cc-transcript --version")

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
