cask "tokenomics" do
  version "2.6.2"
  sha256 "b5c044f3cd112b27ac533b29bed7424867d0a023d03c3c112ec17f9d0b6b6c2f"

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
    Tokenomics updates automatically in-app via Sparkle.
    Use the built-in updater — `brew upgrade` is not supported for this cask.
  EOS
end
