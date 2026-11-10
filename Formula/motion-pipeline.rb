class MotionPipeline < Formula
  desc "Reusable kinetic-typography render pipeline with a no-code project menu (10-bit masters)"
  homepage "https://github.com/haiggoh/motion-pipeline"
  # release asset built with `git archive` (deterministic); the auto-generated
  # archive/refs/tags tarball is NOT byte-stable across downloads
  url "https://github.com/haiggoh/motion-pipeline/releases/download/v0.5.1/mp-0.5.1.tar.gz"
  sha256 "e7853ab17a084ca6c4b74959da56afae319c5c2b9d60f264fe3f52586bf18fbc"
  license "Apache-2.0"

  depends_on "python@3.14"
  depends_on "ffmpeg"

  def install
    libexec.install Dir["*"]

    (bin/"motion-pipeline").write <<~EOS
      #!/bin/bash
      # motion-pipeline launcher: keeps a per-user venv under the Homebrew cache with the
      # runtime deps, and runs the shipped package straight from libexec via PYTHONPATH
      # (no build step — the package uses uv_build, which we don't want to require here).
      set -euo pipefail
      venv="$HOME/.cache/homebrew/motion-pipeline/venv"
      if [ ! -x "$venv/bin/python" ]; then
        mkdir -p "$(dirname "$venv")"
        "#{Formula["python@3.14"].opt_bin}/python3.14" -m venv "$venv"
        # install ALL runtime deps from the shipped pyproject (not a hardcoded subset —
        # v0.4.0 shipped pillow in pyproject but the launcher installed only textual+numpy,
        # so the font menu crashed with ModuleNotFoundError: PIL)
        deps="$("$venv/bin/python" -c 'import tomllib; print(" ".join(tomllib.load(open("'"#{opt_libexec}"'/pyproject.toml", "rb"))["project"]["dependencies"]))')"
        "$venv/bin/pip" install --quiet $deps
      fi
      PYTHONPATH="#{opt_libexec}" exec "$venv/bin/python" -m motion_pipeline "$@"
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
