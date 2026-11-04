# Changelog

## 1.0.1 — 2026-11-04

### Fixed
- Clean, Review, Done, Select All and Scan Again buttons (and Uninstall / Show in Finder in Apps)
  did nothing when clicked on macOS 26. They now use the system glass button styles.

### Improved
- Apps: placeholder rows while apps are found, a progress bar while sizes are measured,
  animated sizes, and a smooth reorder when measuring finishes.
- Apps: selecting an app builds its details in with a short staggered animation.
- Locked areas (e.g. Trash) now explain how to grant Full Disk Access before opening
  System Settings, and YK Cleaner checks again when you come back.

### Note
- Builds are not notarized. After updating, you may need to turn YK Cleaner off and on again
  in Privacy & Security › Full Disk Access.

## 1.0.0 — 2026-11-04

First release.

### Cleaner
- Scans Trash, app caches, logs & crash reports, Xcode junk, developer caches, old temp files,
  and (admin) system caches and logs; shows size per area.
- Include/skip areas or individual files; details panel with Quick Look (Space).
- Permanent cleaning with confirmation; result shown inline.

### Apps
- Lists installed apps with size, data size and last-opened date; search and sort.
- Finds leftovers in `~/Library` by bundle ID (name-only matches start unticked).
- Uninstall or remove data only — items go to the Trash; admin-installed apps via Finder.

### Interface
- Liquid Glass design on macOS 26 (material fallback on 14–15), morphing action buttons.
- Menu commands and keyboard shortcuts for every action; VoiceOver labels; Reduce Motion support.
