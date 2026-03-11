cask "tokenomics" do
  version "2.4.4"
  sha256 "7c6401007e9e0ffccf0bd07d3263890d483759a15200e73610db202f69a98ede"

  url "https://github.com/rob-stout/Tokenomics/releases/download/v#{version}/Tokenomics-#{version}.dmg"
  name "Tokenomics"
  desc "Menu bar app that tracks AI coding tool usage at a glance"
  homepage "https://github.com/rob-stout/Tokenomics"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Tokenomics.app"

  postflight do
    system_command "/usr/bin/pkill", args: ["-f", "Tokenomics.app"], sudo: false
    sleep 1
    system_command "/usr/bin/open", args: ["/Applications/Tokenomics.app"], sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Tokenomics",
    "~/Library/Caches/com.robstout.tokenomics",
    "~/Library/Preferences/com.robstout.tokenomics.plist",
  ]
end
