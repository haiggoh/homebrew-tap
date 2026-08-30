require "json"

class ClaudeCodeTranscriptDistiller < Formula
  desc "Distill Claude Code transcripts into compact evidence and indexed handoffs"
  homepage "https://github.com/haiggoh/Claude-Code-Transcript-Distiller"
  url "https://github.com/haiggoh/Claude-Code-Transcript-Distiller/releases/download/v0.8.0/claude-code-transcript-distiller-0.8.0.tar.gz"
  sha256 "d7e6d9f629082d1621c8297a6876dee89e1cb148bf0700e635714c6391061b85"
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
