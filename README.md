# YK Cleaner

A native macOS (SwiftUI) app with a Liquid Glass interface for freeing up disk space.

- **Cleaner** finds and removes junk: Trash, app caches, logs and crash reports, Xcode leftovers,
  developer caches (npm, Gradle, CocoaPods, `~/.cache`), old temp files and, with your admin
  password, system caches and logs.
- **Apps** lists your installed apps with their size and last-opened date, and uninstalls
  them along with the data they left in `~/Library` (support files, caches, containers,
  preferences, saved state, logs, launch agents).

## Build

    ./build-app.sh

Produces `build/YK Cleaner.app`. Drag it to /Applications. Requires macOS 14+ (Liquid Glass
needs macOS 26; older systems get frosted materials) and the Xcode Command Line Tools
(`xcode-select --install`). No Xcode needed.

## Using it

- Switch sections with the toolbar control or **⌘1** / **⌘2**.
- **Cleaner**: click a card to include or skip it, and click **ⓘ** to see and untick
  individual files. In that panel, Space opens Quick Look. Press **Clean** (⌘⌫) and confirm.
- **Apps**: pick an app, untick any files you want to keep, then press **Uninstall** or Delete.
  Untick the app itself to remove only its data.
- Shortcuts are in the **Clean** menu: ⌘R rescan, ⇧⌘A / ⇧⌘D select or deselect all areas,
  ⌥⌘I details.

## Safety

- Scanning is read-only. Nothing is removed until you confirm.
- **Cleaner deletes permanently.** It only removes the *contents* of the known junk folders,
  never the folders themselves.
- **Apps moves items to the Trash**, so you can put them back from Finder. It only touches
  `/Applications`, `~/Applications` and `~/Library`. System apps, Safari and YK Cleaner itself
  are never listed.
- App leftovers are matched by bundle ID. Folders matched only by the app's name are shown
  in orange and left unticked, so check them yourself.
- Running apps must be quit first; there's a **Quit** button.

## Permissions

- Cleaning the Trash needs **Full Disk Access** (System Settings › Privacy & Security).
- System Caches / System Logs ask for your administrator password.
- Apps installed by an administrator are moved to the Trash through Finder. The first time,
  macOS asks to let YK Cleaner control Finder, and then Finder may ask for your password.
