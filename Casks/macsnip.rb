cask "macsnip" do
  version "1.0.1"
  sha256 "1738908f6436803d67a606dac7d0c8a9881e04dcbb6da0116132e6f1089363fa"

  url "https://github.com/henrikhestnes/MacSnip/releases/download/v#{version}/MacSnip.zip"
  name "MacSnip"
  desc "Ubuntu-style screenshot tool for the menu bar"
  homepage "https://github.com/henrikhestnes/MacSnip"

  depends_on macos: :sonoma

  app "MacSnip.app"

  uninstall quit: "io.macsnip.app"

  zap trash: "~/Library/Preferences/io.macsnip.app.plist"

  caveats <<~EOS
    This build is signed with a self-signed certificate and has not been notarized by Apple.

    MacSnip needs Screen Recording access. If you are upgrading from 1.0.0, remove MacSnip from
    System Settings → Privacy & Security → Screen & System Audio Recording, add it again,
    and relaunch it. Later upgrades keep the permission.
  EOS
end
