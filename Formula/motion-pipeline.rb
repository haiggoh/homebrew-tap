class MotionPipeline < Formula
  desc "Reusable kinetic-typography render pipeline with a no-code project menu (10-bit masters)"
  homepage "https://github.com/haiggoh/motion-pipeline"
  # release asset built with `git archive` (deterministic); the auto-generated
  # archive/refs/tags tarball is NOT byte-stable across downloads
  url "https://github.com/haiggoh/motion-pipeline/releases/download/v0.6.3/mp-0.6.3.tar.gz"
  sha256 "8c1738ffc9bae608453b1ed229bc80ef0ebb713d50848a73e70e12fb0811fbcc"
  license "Apache-2.0"

  depends_on "python@3.14"
  depends_on "ffmpeg"
  depends_on "whisper-cpp" # speech engine for the transcript aligner (0.7.0: model self-installs)

  def install
    libexec.install Dir["*"]

    (bin/"motion-pipeline").write <<~EOS
      #!/bin/bash
      # motion-pipeline launcher: keeps a per-user venv under the Homebrew cache with the
      # runtime deps, and runs the shipped package straight from libexec via PYTHONPATH
      # (no build step — the package uses uv_build, which we don't want to require here).
      set -euo pipefail
      venv="$HOME/.cache/homebrew/motion-pipeline/venv"
      py314="#{Formula["python@3.14"].opt_bin}/python3.14"
      # install ALL runtime deps from the shipped pyproject (not a hardcoded subset —
      # v0.4.0 shipped pillow in pyproject but the launcher installed only textual+numpy,
      # so the font menu crashed with ModuleNotFoundError: PIL). The stamp is the sha256
      # of the dependency LIST: a brew upgrade that adds a dep (e.g. 0.7.0's pypdf) resyncs
      # the existing venv instead of leaving it stale.
      deps_py="$venv/bin/python"
      [ -x "$deps_py" ] || deps_py="$py314"
      deps="$("$deps_py" -c 'import tomllib; print(" ".join(tomllib.load(open("'"#{opt_libexec}"'/pyproject.toml", "rb"))["project"]["dependencies"]))')"
      stamp="$(printf '%s' "$deps" | shasum -a 256 | cut -d' ' -f1)"
      if [ ! -x "$venv/bin/python" ] || [ "$(cat "$venv/.mp-deps" 2>/dev/null)" != "$stamp" ]; then
        mkdir -p "$(dirname "$venv")"
        [ -x "$venv/bin/python" ] || "$py314" -m venv "$venv"
        "$venv/bin/pip" install --quiet $deps
        printf '%s' "$stamp" > "$venv/.mp-deps"
      fi
      PYTHONPATH="#{opt_libexec}" exec "$venv/bin/python" -P -m motion_pipeline "$@"
    EOS
  end

  def caveats
    <<~EOS
      The menu and renderer additionally need the pinned web toolchain (one-time):

        brew install fnm uv
        fnm install 24.19.0
        cd "$(brew --prefix)/libexec/motion-pipeline"  # or your own checkout
        npm install
        npx --yes @puppeteer/browsers install chrome-headless-shell@156.0.8078.4 --path ~/.cache/motion-pipeline/chrome

      See the README quickstart for the full list and the sample project.
    EOS
  end

  test do
    assert_predicate bin/"motion-pipeline", :executable?
    assert_match "usage", shell_output("#{bin}/motion-pipeline --help").downcase
    assert_equal version.to_s, shell_output("#{bin}/motion-pipeline --version").strip.sub("motion_pipeline ", "")
  end
end
