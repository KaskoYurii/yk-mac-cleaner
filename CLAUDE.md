# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

YK Cleaner — a native macOS SwiftUI app (macOS 14+, Liquid Glass on macOS 26+) with two sections:
- **Cleaner**: scans known junk folders (Trash, `~/Library/Caches`, logs, Xcode/dev caches, old temp files, admin-only `/Library/Caches` and `/Library/Logs`) and deletes their contents permanently.
- **Apps**: lists installed apps with their leftover data in `~/Library` and moves them to the Trash.

## Build & run

```bash
./build-app.sh                      # compiles with swiftc, makes icon, ad-hoc signs → build/YK Cleaner.app
open "build/YK Cleaner.app"
```

To replace the copy the user runs from /Applications after a build:

```bash
osascript -e 'quit app "YK Cleaner"'; rm -rf "/Applications/YK Cleaner.app" && cp -R "build/YK Cleaner.app" /Applications/ && open "/Applications/YK Cleaner.app"
```

- **No SwiftPM / no Xcode project.** Only Command Line Tools are installed, and SwiftPM's manifest linking is broken in this toolchain. `build-app.sh` calls `swiftc` directly on `Sources/YKCleaner/*.swift` (Swift 5 language mode, `-parse-as-library`, target macOS 14). New source files are picked up automatically.
- The CLT install has a stale `usr/include/swift/module.modulemap` that redefines `SwiftBridging`. `build-app.sh` works around it with a VFS overlay (`build/vfs.yaml`). Any ad-hoc `swiftc` invocation must pass the same flags: `-vfsoverlay build/vfs.yaml -Xcc -ivfsoverlay -Xcc build/vfs.yaml`.
- No tests and no linter. To exercise non-UI logic, compile a scratch `main.swift` together with only the needed sources (e.g. `AppScanner.swift Scanner.swift Models.swift`) using the flags above. Keep such harnesses read-only; never run deletion code against the real filesystem.
- **Versioning**: `VERSION` holds the marketing version (semver); `build-app.sh` stamps it into `CFBundleShortVersionString` and uses `git rev-list --count HEAD` as `CFBundleVersion`. To release: bump `VERSION`, add a `CHANGELOG.md` entry, commit, then `Scripts/release.sh --publish` (universal `UNIVERSAL=1` build → `dist/*.dmg` + `.zip`, tags `vX.Y.Z`, pushes the tag, creates the GitHub release via `gh` with notes taken from the CHANGELOG section). Builds are ad-hoc signed and not notarized.
- `Resources/Info.plist` is copied into the bundle as-is. It includes `NSAppleEventsUsageDescription`, which the Finder fallback in `AppTrasher` needs.

## Architecture

**State**: two `@MainActor @Observable` models are created once in `YKCleanerApp` and shared by the views and the menu bar commands (`CleanerCommands`):
- `CleanerModel`: scan results, selected categories (saved to UserDefaults), excluded items, and UI state that commands also drive (`section`, `showInspector`, `inspectorCategoryID`, `showCleanConfirmation`, `finishedReport`). Per-category sizes are cached in `cleanableSizes`/`grandTotal` and recomputed in `didSet` of `results`/`excluded`. Don't compute sizes by filtering items inside view bodies.
- `AppsModel`: installed apps, per-app `AppDetails` (measured in the background, 4 at a time), unticked files, running bundle IDs (kept current through NSWorkspace notifications), and trash state.

**Filesystem work** is done in stateless enums run off the main actor with `Task.detached` / task groups:
- `Scanner`: lists the direct children of each `CleanCategory.roots` and measures them. `CleanCategory.all` in `Models.swift` is the single list of junk locations.
- `Cleaner`: permanent deletion. User folders use `FileManager.removeItem`. Admin categories run one `osascript … with administrator privileges` `rm -rf`. **Safety invariant:** an item is only deleted if it is a *direct child* of one of its category's roots. Never delete the roots themselves.
- `AppScanner` / `AppTrasher`: find apps in `/Applications` and `~/Applications`, plus leftovers in `~/Library` matched by bundle ID (exact name or `id.` prefix). Data belonging to a longer installed bundle ID is skipped. Matches by app name only are flagged `matchedByName` and start unticked. `AppTrasher` only moves items to the **Trash** (never deletes) and refuses paths outside `/Applications/`, `~/Applications/` and `~/Library/`. Items it can't move are retried through Finder via AppleScript, which handles the admin password prompt.

**UI composition**:
- `RootView` keeps **both** sections alive in a ZStack and cross-fades them. Hidden sections get `.disabled(true)` so their keyboard shortcuts don't fire. The shared `AuroraBackground`, navigation title/subtitle and toolbar live in `RootView`, not in the section views. Put new toolbar items there, per section.
- Cleaner: `ContentView` → `HeroView` (ring, headline, morphing glass action pills), `CategoryGrid`/`CategoryCard`, and a **floating overlay** `DetailsPanel` that wraps `CategoryInspector`. The panel is a custom overlay rather than `.inspector` on purpose: the inspector resized the content, which made the grid reflow and blink.
- Apps: `AppsView` = `AppList` (with its own `SearchField`) + `AppDetailView`.

## Design rules (from the installed skills in `.claude/skills/`)

The project uses the `swiftui-liquid-glass`, `swiftui-expert-skill` and `macos-design-guidelines` skills. Conventions already applied:
- Use the helpers in `Glass.swift` (`glassCard`, `glassCapsule`, `glassCircle`, `glassMorphID`, `GlassGroup`, `hardTopScrollEdge`). They gate on `#available(macOS 26)` and fall back to materials. Apply glass *after* layout modifiers. Use `interactive` only on tappable things. Group neighbouring glass in a `GlassGroup` whose spacing matches the layout spacing. Never put glass on top of glass (the hero is plain content for this reason).
- Morphing pills share one `@Namespace` + `glassMorphID` inside one `GlassGroup`, animated on a phase value. Build tappable pills with `GlassPillButton` (system `.glass`/`.glassProminent` styles on macOS 26). A plain `Button` whose label has interactive glass + `glassEffectID` inside a `GlassEffectContainer` swallows the click and the action never fires.
- Performance lessons: keep `AuroraBackground` **static**, because animating it forces every glass surface to re-render each frame. Avoid hover scale effects on cards that reflow. Don't do disk I/O in row bodies (icons are cached per type in `FileIcon` and per app in `AppIconCache`). When a list's whole data set changes, replace it with `.id(...)` instead of letting it diff.
- Mac conventions: every action has a menu command and shortcut in `CleanerCommands`. Tappable things are `Button`s with accessibility labels. Destructive permanent deletes need a confirmation dialog. Show results inline, not in alerts. Respect Reduce Motion.
