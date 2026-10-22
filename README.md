# MacSnip

An Ubuntu-style screenshot tool for the macOS menu bar. Swift and AppKit, with no dependencies. Requires macOS 14 or newer.

Press **Hyper+P**. The screen freezes and dims, and a toolbar appears at the bottom, as in GNOME's screenshot UI. The screenshot is copied to the clipboard and saved to `~/Pictures/Screenshots/2026-10-22_14.32.05.png`.

## Install

```sh
brew install --cask henrikhestnes/tap/macsnip
```

Update with `brew update` and `brew upgrade --cask macsnip`. You can also download `MacSnip.zip` from the [latest release](https://github.com/henrikhestnes/MacSnip/releases/latest) and move **MacSnip.app** to **Applications**. The release is ad-hoc signed and not notarized by Apple, so macOS may block it through Gatekeeper.

To build from source instead:

```sh
./scripts/build.sh
cp -R dist/MacSnip.app /Applications/
open /Applications/MacSnip.app
```

MacSnip turns on **Launch at Login** the first time it runs. Turn it off from the menu bar icon; MacSnip won't turn it back on.

On first launch, macOS asks for **Screen Recording** access. Enable MacSnip in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen MacSnip.

The build is ad-hoc signed, so macOS treats every rebuild or upgrade as a new app and silently stops honoring the permission. After rebuilding, remove MacSnip from that list (−), add it again, and relaunch. To avoid this, sign with a stable certificate: `SIGN_IDENTITY="Apple Development: …" ./scripts/build.sh`.

## Using it

| Key / action | Effect |
| --- | --- |
| **Hyper+P** (⌃⌥⌘P or ⌃⌥⌘⇧P) | Freeze the screen and start a capture |
| Drag | Select an area; drag inside it to move it, drag the handles to resize it |
| **Enter**, **Space**, **⌘C**, double-click, or the round button | Capture the selection |
| **S** / **C** / **W** | Selection / Screen / Window mode |
| Click (Screen or Window mode) | Capture that display or window |
| Arrow keys (⇧ for 10 pt) | Nudge the selection |
| **Esc** or right-click | Cancel |

The last selection is restored the next time, as on Ubuntu. Window captures contain only the window itself, without overlapping windows. Selections can span displays. After each capture, a thumbnail appears in the bottom-right corner. Click it to open the screenshot, or drag it into another app.

## Settings

Menu bar icon → **Settings…**:

- **Capture shortcut:** click it and press new keys. As in MacMural, shortcuts use Carbon hot keys, so no Accessibility or Input Monitoring permission is needed. Any shortcut that contains ⌃⌥⌘ counts as a Hyper shortcut and is registered with and without ⇧, so it works whichever way Caps Lock is remapped to Hyper. Conflicts with macOS shortcuts are rejected.
- **Save folder:** defaults to `~/Pictures/Screenshots`.
- **Capture as soon as the mouse is released:** skips the confirmation step, like the older gnome-screenshot.
- **Shutter sound** and **thumbnail:** each can be turned off.

## File names

Names follow `yyyy-mm-dd_hh.mm.ss` on a 24-hour clock, for example `2026-10-22_14.32.05.png`. Every field is zero-padded and the largest unit comes first, so sorting by name in Finder or `ls` matches the order the screenshots were taken. The time uses dots because Finder displays `:` as `/`. If a name is already taken, MacSnip uses the next free second instead of adding a suffix, so the order still holds.

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, run `./scripts/build.sh --universal`, put the new version and the SHA-256 of `dist/MacSnip.zip` in `Casks/macsnip.rb`, and write `releases/vX.Y.Z.md`. `./scripts/publish.sh --check` validates everything offline; `./scripts/publish.sh` tags the release, uploads the ZIP, and updates the cask in [henrikhestnes/homebrew-tap](https://github.com/henrikhestnes/homebrew-tap).
