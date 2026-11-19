cask "echoprism" do
  version "0.1.27"
  sha256 "0e246a29ff621aeee6c3bc91a7b21fe7a2d17ccb6120480e7ae4b8b8ca05501c"

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
