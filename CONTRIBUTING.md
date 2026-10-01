# Contributing to CleanMyDev

Thanks for looking under the hood. This is a tool that deletes files, so the bar for changes that touch scanning or cleaning is higher than for UI work. Read the safety section before anything else.

## Ground rules

- **Nothing deletes without passing `SafetyGuard`.** Every removal goes through `CleaningEngine`, which refuses protected system paths, never-touch folders, and anything inside an Active or Pinned project. Do not add a code path that calls `FileManager.removeItem` or `trashItem` directly.
- **Quarantine is the default.** New cleanable categories must work with quarantine (move + manifest + restore). Permanent deletion is a user choice, never a default.
- **Never hardcode a user's paths.** Projects are discovered by marker files; tools are discovered from their own conventions (`~/.nvm`, `/opt/homebrew/Cellar`, `docker ps` labels). If you need a path, it belongs in `CMConstants` with a comment saying which tool owns it.
- **Review-only by default.** A new `ScanCategory` is `autoSelect: false` unless its contents are provably regenerable. Database data, VM disks, and anything a user authored is `removal: .never`.
- **Honest sizes.** Docker images use `UniqueSize`; directories are sized by allocated blocks with hard links counted once.

## Setup

```bash
git clone https://github.com/Zouuabi/CleanMyDev.git
cd CleanMyDev
cd CleanCore && swift test          # engine tests, no Xcode project needed
cd .. && open CleanMyDev.xcodeproj  # Xcode 26+, macOS 26 SDK
```

Signing: pick your own development team in the target's Signing settings, or create a self-signed "Code Signing" certificate in Keychain Access and set it as `CODE_SIGN_IDENTITY`. A stable signature matters: macOS ties Full Disk Access to the signature, and an ad-hoc build gets re-prompted on every rebuild.

Useful launch arguments while developing: `--open <sidebar item>`, `--scan`, `--dump-projects <file>`, `--demo smartcare|projects|devstack`, `--debug-telemetry`, `--skip-fda`.

## Layout

```
CleanCore/            SwiftPM package, Swift 6 strict concurrency, no UI
  Safety/             SafetyGuard, CleanFilter, CMConstants
  Scanning/           ScanTarget, TargetedScanner, SizeCache, ScanTelemetry
  Cleaning/           CleaningEngine (dry-run / trash / quarantine / permanent), QuarantineStore
  Projects/           ProjectKind table, ProjectDetector, ProjectClassifier, ProjectRegistry
  Modules/            One ScanModule per sidebar area, DevStackInventory
  Services/           Docker, simulators, process probe, system stats
  Hardware/           SMC, IOHID sensors, speed test
  DiskMap/            Disk tree scanner and treemap layout
CleanMyDev/           SwiftUI app: AppModel, RadialMapView, module screens, menu bar
```

## Adding a scan module

1. Add cases to `ScanCategory` with a display name, subtitle, symbol, `autoSelect`, and `eligibleForAutoClean`.
2. Implement `ScanModule.scan(context:)` returning `[ScanResult]`. Use `TargetedScanner` for files; implement a `VirtualCleaner` for non-file items (see `DockerService`).
3. Register it in `AllModules.make()` and map it in `SidebarItem.moduleIDs`.
4. Add a hero bullet in `HeroView.categories(for:)` and a tint/symbol in `ResultGraphView`.
5. Add tests in `CleanCore/Tests` for any pure decision logic.

## Pull requests

- One focused change per PR. Explain what can now be deleted that couldn't before, and why that's safe.
- `cd CleanCore && swift test` must pass. Run the relevant rows of `QA-CHECKLIST.md` and say which ones.
- Screenshots or a short recording for UI changes.
- Keep commits readable; the history is part of the documentation.

## Reporting a bug that deleted something it shouldn't have

Open an issue with the `[DELETED]`/`[QUARANTINED]` lines from `~/Library/Logs/CleanMyDev/operations.log` and the category it came from. If it went through quarantine, restore from the Quarantine screen first.
