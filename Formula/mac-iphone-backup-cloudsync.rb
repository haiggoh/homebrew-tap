class MacIphoneBackupCloudsync < Formula
  desc "Zip the newest local iPhone backup into a cloud-synced folder"
  homepage "https://github.com/haiggoh/mac-iphone-backup-cloudsync"
  url "https://github.com/haiggoh/mac-iphone-backup-cloudsync/releases/download/v1.1.0/mac-iphone-backup-cloudsync-1.1.0.tar.gz"
  sha256 "b46011acbe461cbdef4932dd3cec5f3e88c78f6081836956e726ecc154367f4a"
  license "MIT"

  # Prebuilt ad-hoc-signed bundle (macOS 13+); building from source needs Xcode, so the
  # release asset ships the .app and this formula just installs it.
  def install
    libexec.install Dir["*.app"]
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
