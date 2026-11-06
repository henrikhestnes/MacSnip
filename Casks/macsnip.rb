cask "macsnip" do
  version "1.1.0"
  sha256 "1c3e9607ca0b00812788c4b593218c2820a4b567c09bcefb83a1508fa94f0fe0"

  url "https://github.com/henrikhestnes/MacSnip/releases/download/v#{version}/MacSnip.zip"
  name "MacSnip"
  desc "Ubuntu-style screenshot tool for the menu bar"
  homepage "https://github.com/henrikhestnes/MacSnip"

  depends_on macos: :sonoma

  app "MacSnip.app"

  uninstall quit: "io.macsnip.app"

  zap trash: "~/Library/Preferences/io.macsnip.app.plist"

  caveats "This build is signed with a self-signed certificate and has not been notarized by Apple."
end
