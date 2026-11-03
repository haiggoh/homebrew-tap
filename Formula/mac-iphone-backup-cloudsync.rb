class MacIphoneBackupCloudsync < Formula
  desc "Zip the newest local iPhone backup into a cloud-synced folder"
  homepage "https://github.com/haiggoh/mac-iphone-backup-cloudsync"
  url "https://github.com/haiggoh/mac-iphone-backup-cloudsync/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "bf5f1f488bd2caa799a42949e7cce4100f9d6b3ca7cf6a77c4ecbdf3ad810810"
  license "MIT"

  # Built from the git tag's source archive, not the prebuilt release asset: SPM compiles
  # with the Command Line Tools alone (no full Xcode) and the bundle is ad-hoc-signed
  # locally, so the installed .app carries no quarantine xattr and launches without a
  # Gatekeeper "unidentified developer" prompt. The prebuilt asset stays published on the
  # release page for direct download; this formula no longer uses it.
  #
  # The steps mirror the repo's build.sh, except the SPM call adds --disable-sandbox:
  # SwiftPM sandboxes its subprocesses via sandbox-exec, which cannot nest inside
  # Homebrew's own install sandbox ("sandbox_apply: Operation not permitted", Xcode 26
  # toolchain) — ./build.sh verbatim therefore fails under `brew install`.
  def install
    system "swift", "build", "-c", "release", "--product", "iPhoneBackup", "--disable-sandbox"
    bin_path = `swift build -c release --product iPhoneBackup --disable-sandbox --show-bin-path`.strip
    app = "build/iPhone Backup.app"
    mkdir_p "#{app}/Contents/MacOS"
    mkdir_p "#{app}/Contents/Resources"
    cp "#{bin_path}/iPhoneBackup", "#{app}/Contents/MacOS/iPhoneBackup"
    cp "Info.plist", "#{app}/Contents/Info.plist"
    cp "Resources/AppIcon.icns", "#{app}/Contents/Resources/AppIcon.icns"
    Dir["Resources/*.lproj"].each { |lproj| cp_r lproj, "#{app}/Contents/Resources/" }
    (Pathname(app)/"Contents/PkgInfo").write "APPL????"
    system "codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", app
    system "codesign", "--verify", app
    libexec.install app
    bin.write_exec_script "mac-iphone-backup-cloudsync", <<~EOS
      #!/bin/sh
      exec "#{libexec}/iPhone Backup.app/Contents/MacOS/iPhoneBackup" "$@"
    EOS
  end

  def caveats
    <<~EOS
      The app bundle is installed at:
        #{libexec}/iPhone Backup.app
      Launch it from there (or copy it to ~/Applications). It reads
      ~/Library/Application Support/MobileSync/Backup, which needs Full Disk Access:
      System Settings > Privacy & Security > Full Disk Access, on first run.
      Ad-hoc signing means the code identity changes per build, so macOS may ask you to
      re-grant that permission after an upgrade.
    EOS
  end

  test do
    assert_predicate libexec/"iPhone Backup.app/Contents/MacOS/iPhoneBackup", :executable?
    assert_predicate bin/"mac-iphone-backup-cloudsync", :executable?
  end
end
