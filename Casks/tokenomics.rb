cask "tokenomics" do
  version "2.4.9"
  sha256 "5db027260787383ba7823ff5ed4cde7f48eb66a8ace1e635a12b6ae05bc38f16"

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
