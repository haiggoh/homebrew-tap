require "json"

class ClaudeCodeTranscriptDistiller < Formula
  desc "Distill native Claude Code transcripts into compact, line-addressable evidence and indexed LLM handoffs"
  oldname "claude-code-session-bundle"

  # The repo is mid-rename (claude-code-session-bundle → claude-code-transcript-distiller);
  # this is the new slug with GitHub's redirect in place, and the formula's own rename is
  # what makes the redirect fire.
  homepage "https://github.com/haiggoh/claude-code-transcript-distiller"
  url "https://github.com/haiggoh/claude-code-session-bundle/releases/download/v0.7.0/claude-code-transcript-distiller-0.7.0.tar.gz"
  sha256 "e9d5fdaee6e6b4de4cc54a718a137165e720a3369bd4deedc5984ba6dba0ea09"
  license "MIT"

  depends_on "python@3.14"

  def install
    libexec.install Dir["*"]
    # 0.6.x shipped the entry script under its pre-rename filename; keep that path
    # valid next to cc_transcript.py so scripts written against 0.6.x keep working.
    (libexec / "compact_session_bundle.py").write_file((libexec / "cc_transcript.py").read)
    bin.install_symlink libexec/"cc_transcript.py" => "cc-transcript"
  end

  test do
    # Derived from the url's version rather than restated: a literal here has to be
    # bumped in lockstep with the url, and when it isn't the test either fails for the
    # wrong reason or (as happened at 0.5.0, where both were stale) passes against a
    # superseded release.
    assert_equal "#{version}\n", shell_output("#{bin}/cc-transcript --version")

    cp libexec/"cc_transcript.py", testpath
    system formula_opt_bin("python@3.14")/"python3",
           "-m", "py_compile",
           testpath/"cc_transcript.py"

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
