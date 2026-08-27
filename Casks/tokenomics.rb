cask "tokenomics" do
  version "2.9.1"
  sha256 "5670576dbd10f9fb925a3992230d5a27ce88a5a4235346dfc2ab1d70feda0381"

  url "https://trytokenomics.com/download/dmg/v#{version}",
      verified: "trytokenomics.com/download/"
  name "Tokenomics"
  desc "Menu bar app that tracks AI coding tool usage at a glance"
  homepage "https://github.com/rob-stout/Tokenomics"

  # Live-check against GitHub directly — the trytokenomics.com URL is a
  # counted redirect, not a list of releases.
  livecheck do
    url "https://github.com/rob-stout/Tokenomics/releases/latest"
    strategy :github_latest
  end

  auto_updates true

  app "Tokenomics.app"

  uninstall quit:       "com.robstout.tokenomics",
            login_item: "Tokenomics"

  zap trash: [
    "~/Library/Application Support/Tokenomics",
    "~/Library/Caches/com.robstout.tokenomics",
    "~/Library/Containers/com.robstout.tokenomics",
    "~/Library/Containers/com.robstout.tokenomics.widgets",
    "~/Library/Group Containers/group.com.robstout.tokenomics",
    "~/Library/HTTPStorages/com.robstout.tokenomics",
    "~/Library/Preferences/com.robstout.tokenomics.plist",
    "~/Library/Logs/Tokenomics",
    "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/Vivaldi/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/com.operasoftware.Opera/NativeMessagingHosts/com.tokenomics.bridge.json",
    "~/Library/Application Support/Arc/NativeMessagingHosts/com.tokenomics.bridge.json",
  ]

  caveats <<~EOS
    Tokenomics updates automatically in-app via Sparkle.
    Use the built-in updater — `brew upgrade` is not supported for this cask.
  EOS
end
