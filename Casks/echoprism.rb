cask "echoprism" do
  version "0.1.13"
  sha256 "024bd368abbbbdbfb06a856b8751587ecd8f3263ec8f34e8956a2efecf482052"

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
