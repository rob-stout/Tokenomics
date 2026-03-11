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

  auto_updates true

  app "Tokenomics.app"

  uninstall quit: "com.robstout.tokenomics"

  zap trash: [
    "~/Library/Application Support/Tokenomics",
    "~/Library/Caches/com.robstout.tokenomics",
    "~/Library/Preferences/com.robstout.tokenomics.plist",
  ]

  caveats <<~EOS
    Tokenomics updates automatically via Sparkle.
    You don't need to use `brew upgrade` — updates are handled in-app.
  EOS
end
