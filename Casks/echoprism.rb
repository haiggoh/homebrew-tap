cask "echoprism" do
  version "0.1.25"
  sha256 "6f58bc090cf39c927fcb196fb982ca1aa977bd65187a667fe3b4a9987335605a"

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
