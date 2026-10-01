# CleanMyDev — notes for coding agents

Read `CONTRIBUTING.md` and `SECURITY.md` first; the safety rules there are non-negotiable.

## Build and test

```bash
cd CleanCore && swift test                                   # engine tests (fast, no Xcode project)
xcodebuild -project CleanMyDev.xcodeproj -scheme CleanMyDev \
  -configuration Debug -derivedDataPath build/dd build       # app (macOS 26 SDK, Xcode 26+)
```

Run the built app with `open build/dd/Build/Products/Debug/CleanMyDev.app --args <flags>`, never the raw binary from a sandboxed shell (no window server). Flags: `--open <item>`, `--scan`, `--demo smartcare|projects|devstack`, `--dump-projects <file>`, `--debug-telemetry`, `--skip-fda`.

Screenshots for verification: `screencapture -x -o -l <windowID> out.png`; window IDs via `CGWindowListCopyWindowInfo` (owner "CleanMyDev").

## Architecture in one paragraph

`CleanCore` (SwiftPM, Swift 6 strict) owns everything that touches the disk: `ScanModule`s produce `[ScanResult]` of `FileItem`s, `CleaningEngine` deletes only what `SafetyGuard` allows, `ProjectDetector` + `ProjectClassifier` decide which projects are Active/Idle/Dormant (overrides in `ProjectRegistry`, keyed by git remote), `DevStackInventory` discovers installed tooling, `DockerService`/`SimulatorService` implement `VirtualCleaner` for non-file items. The app (`CleanMyDev/`, Swift 5 mode, default MainActor) has one `AppModel`, one `RadialMapView` that renders every map, and thin module screens.

## Things that bit us, don't repeat them

- Never read the observable `AppModel` from `.commands {}` or a Scene-level binding setter without a change guard: SwiftUI rebuilds the main menu / MenuBarExtra on every model write and spins the main thread at 100%.
- A stable code signature is required. Ad-hoc builds change identity on every rebuild, so macOS re-prompts for Full Disk Access and TCC consent dialogs block scanner threads inside `open()`. That looks like a hung scan; it isn't.
- Docker sizes: use `UniqueSize` from `docker system df -v`, otherwise shared layers are counted many times.
- `URL.path(percentEncoded:)` for the home folder ends with `/`; use `CMConstants.homePath` for prefix work.
- Project discovery must keep walking below a project (monorepos) but skip bundles (`.xcodeproj`, `.app`), tool caches (`~/go/pkg`), and artifact dirs.

## Style

Plain English UI strings, no localisation layer. Teal brand (`ModuleTheme`), Liquid Glass via `glassCard()` and `.glassEffect`, one primary action per screen. Reasons on every cleanable item (`FileItem.reason`) so the user knows why it's offered.
