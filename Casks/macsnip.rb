cask "macsnip" do
  version "1.0.0"
  sha256 "33678ef69e3e4573aa7ade97caf45a8e5be6793ac85234aecff35002c6042cad"

  url "https://github.com/henrikhestnes/MacSnip/releases/download/v#{version}/MacSnip.zip"
  name "MacSnip"
  desc "Ubuntu-style screenshot tool for the menu bar"
  homepage "https://github.com/henrikhestnes/MacSnip"

  depends_on macos: :sonoma

  app "MacSnip.app"

  uninstall quit: "io.macsnip.app"

  zap trash: "~/Library/Preferences/io.macsnip.app.plist"

  caveats <<~EOS
    This build is ad-hoc signed and has not been notarized by Apple.

    MacSnip needs Screen Recording access. After each upgrade, remove MacSnip from
    System Settings → Privacy & Security → Screen & System Audio Recording, add it
    again, and relaunch it.
  EOS
end
