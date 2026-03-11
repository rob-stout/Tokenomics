cask "tokenomics" do
  version "2.4.7"
  sha256 "3fdd972734e4fa0426f753dda639e75891312e4300f1faa8c1bcfe1397955121"

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
