cask "tokenomics" do
  version "2.4.6"
  sha256 "c163f7ca5171b34cf2cdda861ffcc8ed3630bf3ab1d64d9e3f05d7d3f306428d"

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
    sleep 2
    system_command "/usr/bin/open", args: ["/Applications/Tokenomics.app"], sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Tokenomics",
    "~/Library/Caches/com.robstout.tokenomics",
    "~/Library/Preferences/com.robstout.tokenomics.plist",
  ]
end
