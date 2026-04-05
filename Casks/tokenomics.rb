cask "tokenomics" do
  version "2.7.4"
  sha256 "be097e3e69379f189cab3f2ae531b55cd038f8aeb376684f9fb9d3db7ac01b7b"

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
