cask "echoprism" do
  version "0.1.11"
  sha256 "cea59a4e8a6a7c9ed130b2bcd2b52f2c9e88f8d3c8ca5d87c7706e36228623db"

  url "https://github.com/haiggoh/echoprism/releases/download/v#{version}/EchoPrism_#{version}_aarch64.dmg"
  name "EchoPrism"
  desc "Two streams become one — local-first unified YouTube video and podcast player"
  homepage "https://github.com/haiggoh/echoprism"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  auto_updates true
  app "EchoPrism.app"

  zap trash: [
    "~/Library/Caches/app.echoprism",
    "~/Library/Preferences/app.echoprism.plist",
    "~/Library/Saved Application State/app.echoprism.savedState",
    "~/Library/Logs/DiagnosticReports/EchoPrism_*",
  ]
end
