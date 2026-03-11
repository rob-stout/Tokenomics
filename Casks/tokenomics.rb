cask "tokenomics" do
  version "2.4.5"
  sha256 "778a92ed363eaf24bf8be70cd1161d075967c4e67e5b20f60e8ef12e8e99133d"

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
