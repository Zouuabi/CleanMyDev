<p align="center">
  <img src="CleanMyDev/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="CleanMyDev icon" />
</p>

<h1 align="center">CleanMyDev</h1>

<p align="center">
  <strong>A Mac cleaner that understands developers.</strong><br>
  Project-aware junk removal, a map of your dev stack, Docker, simulators, caches, startup items.<br>
  Discovered, not configured. Quarantined, not deleted. Native SwiftUI on macOS 26.
</p>

<p align="center">
  <a href="https://github.com/Zouuabi/CleanMyDev/releases/latest"><img src="https://img.shields.io/github/v/release/Zouuabi/CleanMyDev?style=flat-square&color=2DD4BF" alt="Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey?style=flat-square" alt="macOS 26+" />
  <img src="https://img.shields.io/badge/swift-6-orange?style=flat-square" alt="Swift 6" />
  <img src="https://img.shields.io/badge/telemetry-none-2DD4BF?style=flat-square" alt="No telemetry" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT" />
</p>

<p align="center">
  <img src="docs/media/smartcare.gif" width="880" alt="Smart Care: scan, then review on the map" />
</p>

---

## Why another Mac cleaner

Generic cleaners are blind to the thing that actually fills a developer's disk: `node_modules` in forty projects, three Python venvs per repo, Docker layers, Xcode's DerivedData, half a dozen Node versions under nvm, and the npm cache from every `npx` you ever ran. Worse, they are dangerous around it: the one `node_modules` you must not touch is the one you're shipping on Sunday.

CleanMyDev starts from the projects.

- **Every project on your Mac is found** by its marker files (`package.json`, `pyproject.toml`, `Cargo.toml`, `Podfile`, `.xcodeproj`, `docker-compose.yml`, 20 more) and identified by its git remote, so pins survive renames and moves.
- **Each one gets a status with a reason**: *Active* (commit or file change in the last 14 days, a running compose container, a dev server, or a shell open in it), *Idle*, *Dormant*. You can *Pin* one until a date or mark it *Cleanable*. Nothing inside an Active or Pinned project is ever offered, including its Docker containers and volumes. Sub-packages inherit their monorepo's protection.
- **Only dormant projects give up** their dependencies and build output, and they're shown with "untouched for 94 days" next to the size.

Everything else a cleaner should do is here too, but with the same honesty: Docker image sizes count only unshared layers, database data is shown with a lock and never deleted, and every removal lands in a quarantine you can restore from for 7 days.

## What's inside

| Area | What it does |
|---|---|
| **Smart Care** | One pass over everything below, reviewed on an interactive radial map: modules sized by what they found, categories fanning out, items in a side panel, a checkbox on every bubble. Clean goes to quarantine by default. |
| **Projects** | The map of your projects by status. Pin, unpin, mark cleanable, see why each one is what it is, reveal in Finder. |
| **Dev Stack** | Inventory of what's installed for development: databases and *where their data lives* (Homebrew `var/`, Postgres.app, Docker containers), runtimes and which version is default (nvm, pyenv, rustup, Homebrew), globally installed tools (npm `-g`, pipx, uv, cargo, go), SDKs, VM disks. Copies the right `brew uninstall` / `npm uninstall -g` command instead of guessing. Plus a Ports tab with a kill switch. |
| **System Junk** | User and system caches, logs, crash reports, trash on every volume, leftovers of uninstalled apps, broken preferences and launch agents, editor caches (VS Code, Cursor, Antigravity), AI tool caches (Claude, Codex), chat app caches. |
| **Dev Junk** | npm, pnpm, yarn, bun, pip, uv, poetry, cargo, go, gradle, maven, CocoaPods, Homebrew, Playwright and Cypress browsers, Hugging Face and Torch weights, Xcode DerivedData / Archives / device support, dead simulators, and the dependencies of dormant projects. |
| **Docker** | Unused images (unique size), orphan volumes, exited containers, build cache. Anything attached to an Active or Pinned project is skipped by compose label and image name. |
| **Browsers** | Page caches for Chrome, Edge, Brave, Arc, Firefox, Safari; history only when the browser is closed. Cookies, logins and bookmarks are never touched. |
| **Security** | Known adware families, plus an audit of every launch agent and daemon with its code signature; unsigned programs in user-writable locations and shell payloads are flagged. |
| **Apps** | Installed apps with icon, size, last used, source (App Store / Homebrew / direct), leftovers across 17 `~/Library` folders. Uninstall or remove leftovers only. |
| **Space Lens** | Treemap of any folder with header bands, drill-down, reveal, quarantine. Large & old files tab. |
| **Quarantine** | Every clean is a restorable run with its original paths. Expired runs are purged automatically. |
| **Menu bar** | CPU, memory, disk, CPU temperature, fan rpm with manual control, a network speed test, and your last security check. |

<p align="center">
  <img src="docs/media/projects.gif" width="430" alt="Projects map" />
  <img src="docs/media/devstack.gif" width="430" alt="Dev Stack map" />
</p>

## Install

Download the latest `.dmg` from [Releases](https://github.com/Zouuabi/CleanMyDev/releases/latest), open it, drag **CleanMyDev** to Applications.

The build is signed but not notarized (no Apple Developer Program behind it yet), so the first launch needs **right-click → Open**, or:

```bash
xattr -d com.apple.quarantine /Applications/CleanMyDev.app
```

On first launch the app asks for **Full Disk Access** and refuses to go further without it. That is deliberate: without it macOS hides Mail, Safari and parts of `~/Library`, and consent dialogs would stall scans half way. Nothing leaves your Mac; the only network call is the speed test you trigger yourself.

Requires macOS 26 (Tahoe) or later. Apple Silicon and Intel.

### Build from source

```bash
git clone https://github.com/Zouuabi/CleanMyDev.git
cd CleanMyDev/CleanCore && swift test      # engine tests
cd .. && open CleanMyDev.xcodeproj         # Xcode 26+
```

Pick your own signing team in the target settings (or a self-signed Code Signing certificate). See `CONTRIBUTING.md`.

## Safety model

- **Quarantine first.** Cleaned items move to `~/Library/Application Support/CleanMyDev/Quarantine/<run>/` with a manifest; one click restores a whole run. Trash and permanent delete are options, never defaults.
- **SafetyGuard on every path.** Protected system paths, your never-touch folders, and Active / Pinned projects are refused after symlink resolution. Batches are capped and chunked.
- **Review-only categories.** Large files, project dependencies, Docker images, app leftovers, browser history, startup items: never pre-checked.
- **Never deleted at all.** Database data directories, VM disks, Keychains, SSH keys, Claude's VM bundles. Shown with a lock so you know where the space is.
- **Logged.** `~/Library/Logs/CleanMyDev/operations.log` has every dry-run, quarantine, restore, and error.

## Settings worth knowing

| Setting | Default |
|---|---|
| Active if touched within | 14 days |
| Dormant after | 30 days |
| Default clean mode | Quarantine, 7-day retention |
| Scan roots | your home folder |
| Never touch | Keychains, `.ssh`, `.gnupg`, `.colima`, Claude VM bundles (editable) |
| Scheduled daily run | off; when on, quarantines only the categories you allow |

## Thanks

Engines in `CleanCore` adapt code from [Mac Sai](https://github.com/iliyami/MacSai) (BSD-3), [MacDirStat](https://github.com/phalladar/MacDirStat) (MIT), [kondo](https://github.com/tbillington/kondo) (MIT) and [Stats](https://github.com/exelban/stats) (MIT). Full texts in `THIRD-PARTY-LICENSES.md`.

## License

MIT. See `LICENSE`.
