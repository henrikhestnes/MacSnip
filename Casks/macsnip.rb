cask "macsnip" do
  version "1.1.1"
  sha256 "2b103792bfd005357fde6b9eabda09aae51c3362f479666058c6c08831566bc2"

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
