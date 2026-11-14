cask "echoprism" do
  version "0.1.18"
  sha256 "884da6df03b42d3f3a7c3ed94a95e6361bc9d1a1f6912b3f886fc8bef33733df"

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
