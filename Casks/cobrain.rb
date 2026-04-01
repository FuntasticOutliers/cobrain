cask "cobrain" do
  version :latest
  sha256 :no_check

  url "https://github.com/WeAreOutliers/cobrain/releases/latest/download/cobrain.dmg"
  name "Cobrain"
  desc "A local search engine for your memory"
  homepage "https://github.com/WeAreOutliers/cobrain"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "cobrain.app"

  zap trash: [
    "~/Library/Application Support/dev.cobrain.app",
    "~/Library/Caches/dev.cobrain.app",
    "~/Library/Preferences/dev.cobrain.app.plist",
  ]
end
