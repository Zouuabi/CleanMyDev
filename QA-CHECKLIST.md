# CleanMyDev QA checklist

Run from Xcode (⌘R) or the built app. Every scenario says what to click and what you must see. Tick what passes; note anything else in the "Result" column.

Layout note: results screens open on the **map** (bubbles/radial graph); the list view is one toggle away (top right). Run each scenario in both. Security has two tabs (Malware check, Startup items); Space Lens has Map and Large & old files; Dev Stack has Stack and Ports.

Before you start: Quarantine lives in `~/Library/Application Support/CleanMyDev/Quarantine`, the log in `~/Library/Logs/CleanMyDev/operations.log`.

## 1. Smart Care, scan and review

| Step | Do | Expect | Result |
|---|---|---|---|
| 1.1 | Open the app, Smart Care is selected | Three vitals rings (CPU, Memory, Disk) show live numbers; "Last clean: Never" the first time | |
| 1.2 | Click **Scan** | Ring animates, the module name under it changes (System Junk → Dev Junk → Docker → …), bytes found climbs | |
| 1.3 | Click **Stop** mid-scan | Back to the hero screen within a second, no crash | |
| 1.4 | Scan again, let it finish | Scan done sound; header reads "N items · X GB found"; radial map with Smart Care in the middle, one bubble per module sized by bytes, plus Projects and Dev Stack bubbles | |
| 1.4b | Click a module bubble | Its categories fan out with a spring; click a category → side panel lists its items; ring around a bubble shows how much of it is selected | |
| 1.4c | Click the Projects bubble, then a status satellite | Side panel lists those projects with their status chips; "Open Projects" jumps there | |
| 1.5 | Switch to list view, look at the PROJECTS strip | your active project shows **Pinned**, your pinned project shows **Pinned**; nothing from either appears in any category | |
| 1.6 | Cards marked **Review** (orange) | Their checkbox is empty by default; others are checked | |
| 1.7 | Expand a card (chevron or click the row) | Rows show name, a reason line, a `~/…` path, size, and a magnifier that reveals the file in Finder | |
| 1.8 | Uncheck one row inside a checked card | Card checkbox becomes a "minus"; the Clean button total drops by that row's size | |
| 1.9 | Uncheck the card itself | Every row in it unchecks; total drops by the card size | |

## 2. Clean and restore (the important one)

| Step | Do | Expect | Result |
|---|---|---|---|
| 2.1 | From results, keep only **User Logs** checked (uncheck everything else) | Action bar shows the User Logs size | |
| 2.2 | Open **Options** menu | Quarantine / Move to Trash / Dry run / Delete permanently… | |
| 2.3 | Choose **Dry run** | "Dry run complete" screen, bytes shown, nothing deleted (check a logged path still exists in Finder) | |
| 2.4 | Click **Done**, rescan, select User Logs again, click **Clean** | Cleaning ring, then "Cleaned" with the freed size and "moved to quarantine" text | |
| 2.5 | Click **Open Quarantine** | A run card labelled "Smart Care" with today's time, item count, size, expiry in 7 days | |
| 2.6 | Expand the run | Original paths listed | |
| 2.7 | Click **Restore all** | Card disappears; the files are back at their original paths (check one in Finder) | |
| 2.8 | Clean the same category again, then on the Quarantine screen click **Delete** | Card disappears, folder under `Quarantine/` is gone, log has a `[PURGED]` line | |
| 2.9 | Sidebar footer | "Last clean X min ago · size" appears after a real clean, not after a dry run | |

## 3. Projects and protection

| Step | Do | Expect | Result |
|---|---|---|---|
| 3.1 | Open **Projects** | Bubble map of real projects (no `go/pkg/mod`, no `.xcodeproj` rows), bubble size = deps + build output, colour = status; click a bubble → inspector on the right with artifacts and the status chip; list view via the toggle | |
| 3.2 | Toggle **Only with deps or build output** off | More rows appear (repos with nothing to clean) | |
| 3.3 | Expand FarmManagementSystem | Artifact list is empty now (deps were deleted today), status Idle | |
| 3.4 | On a **Dormant** project (e.g. `extra/skillbey/New project`) open the status chip menu → **Pin until a date…** | Sheet with date picker and 3 days / 1 week / 1 month buttons | |
| 3.5 | Pin it for 3 days | Chip turns cyan "Pinned"; reason "Pinned by you until <date>" | |
| 3.6 | Go to **Dev Junk**, scan | That project's `node_modules`/`.next` are NOT in Project Dependencies / Build Output | |
| 3.7 | Back in Projects, chip menu → **Back to automatic** | Chip returns to Dormant | |
| 3.8 | Rescan Dev Junk | Its artifacts are offered again, reason "Project untouched for N days" | |
| 3.9 | On an **Active** project choose **Mark cleanable** | Chip turns pink "Cleanable"; its deps appear in Dev Junk results after a rescan. Then set it back to automatic | |
| 3.10 | Rename a dormant project folder in Finder, click **Rescan** | Same status and any pin survive (identity is the git remote) | |
| 3.11 | Open a Terminal, `cd` into a Dormant project, Rescan | It becomes Active with reason "A terminal or editor is open in this folder" | |
| 3.12 | Quit the app, relaunch, open Projects | Pins are still there (persisted in `projects.json`) | |

## 4. Docker (nothing here may touch your active project or pinned)

| Step | Do | Expect | Result |
|---|---|---|---|
| 4.1 | Open **Docker**, Scan | Docker Images (Review, unchecked) and Docker Volumes (Review, unchecked); total ≈ what `docker system df` calls reclaimable | |
| 4.2 | Expand Docker Images | No `<pinned-project>-*` image, no `supabase/*` image in use; untagged images named "untagged <id>"; reason mentions shared layers where relevant | |
| 4.3 | Expand Docker Volumes | No `supabase_*` or `<pinned-project>_*` named volume | |
| 4.4 | Check one obviously dead image (e.g. `hello-world:latest`), Clean | Done screen; `docker images` no longer lists it; pinned and your active project containers still `Up` (`docker ps`) | |
| 4.5 | Stop Docker (`colima stop`), Rescan | "Nothing to clean" with no crash (known gap: it should say Docker is unreachable, not "tidy") | |

## 5. Browsers

| Step | Do | Expect | Result |
|---|---|---|---|
| 5.1 | With Chrome open, scan **Browsers** | Browser Caches present, reason ends with "(Chrome is running, cache will refill)"; **no** Chrome History rows | |
| 5.2 | Quit Chrome, Rescan | Browser History card appears (Review, unchecked) | |
| 5.3 | Clean only Browser Caches | Chrome reopens normally, still logged in to sites, bookmarks intact | |

## 6. Uninstaller

| Step | Do | Expect | Result |
|---|---|---|---|
| 6.1 | Open **Uninstaller** | Apps with real icons, version, last used, size; sort by Size / Name / Last used works; search filters live | |
| 6.2 | Toggle **Show Apple apps** | Apple apps appear; selecting one shows "System apps can't be uninstalled" | |
| 6.3 | Select **Linear** (or any app you don't need) | Inspector: icon, source badge (Homebrew / App Store / Direct), app size, leftovers list with checkboxes | |
| 6.4 | Click **Remove leftovers only** | Green confirmation line; app still launches | |
| 6.5 | Click **Uninstall** on an app you really want gone | App disappears from the list; it and its leftovers are in a Quarantine run named "Uninstall <app>" | |
| 6.6 | Restore that run from Quarantine | App is back in /Applications and launches | |

## 7. Space Lens

| Step | Do | Expect | Result |
|---|---|---|---|
| 7.1 | Open **Space Lens**, click **Map home folder** | Progress with file count, then a treemap; folder names in header bands, big files labelled | |
| 7.2 | Hover blocks | Side panel updates with name, path, size, modified date | |
| 7.3 | Double-click `dev` | Breadcrumb becomes `~ › dev`, map re-lays out; click `~` in the breadcrumb to go back | |
| 7.4 | Right-click a block → **Reveal in Finder** | Finder opens at that item | |
| 7.5 | Right-click a block inside your active project → **Move to quarantine…** → confirm | Nothing moves; the log shows `[BLOCKED] … active or pinned project` | |
| 7.6 | **Choose folder…**, pick `~/Downloads` | Map shows only Downloads | |

## 8. Protection

| Step | Do | Expect | Result |
|---|---|---|---|
| 8.1 | **Security → Startup items** | Every launch agent/daemon listed with scope and signature badge; "Only flagged" leaves the 2 flagged ones (BlueStacks cleanup is Unsigned) | |
| 8.2 | Magnifier on a row | Finder reveals the plist | |
| 8.3 | **Security → Malware check** → Check | Either "Nothing to clean" or Known Malware / Suspicious Startup Items cards, all unchecked | |

## 9. Settings and menu bar

| Step | Do | Expect | Result |
|---|---|---|---|
| 9.1 | ⌘, → General: set Dormant to 20 days, rescan Projects | FarmManagementSystem (25 days) becomes Dormant; set it back to 30 | |
| 9.2 | Folders: add `~/dev/your active projectInc` to Never touch, run Smart Care | No row anywhere under that folder; remove it afterwards | |
| 9.3 | Schedule: enable daily run | `~/Library/LaunchAgents/Mouvema.CleanMyDev.daily.plist` exists; `launchctl list | grep CleanMyDev` shows it; disable → plist gone | |
| 9.4 | Menu bar sparkle icon | Popover with CPU/memory/disk rings, CPU temperature, fan rpm with Manual toggle + slider + Apply (asks your password; Auto hands control back), network speed **Test** button showing ↓/↑ Mbps and ping, security card with last check and flag count that opens Security, "Smart Care" button; turning the toggle off in Settings removes the icon | |
| 9.4b | Settings → Sound effects off | No sounds on scan start/done or clean | |
| 9.5 | Log tab | Shows the operations log with today's entries | |

## 10. Dev Stack

| Step | Do | Expect | Result |
|---|---|---|---|
| 10.1 | Open **Dev Stack** | Bubble map grouped by colour; chips filter by group; search narrows live | |
| 10.2 | Click the `postgresql@17 data` bubble | Inspector shows the data dir with a lock (never deletable) and the dump hint | |
| 10.3 | Click `openclaw` | Shows "npm global", size, modified date; the clipboard button copies `npm uninstall -g openclaw` | |
| 10.4 | **Ports** tab | Listening ports with Kill buttons | |

## 11. Robustness

| Step | Do | Expect | Result |
|---|---|---|---|
| 10.1 | Start a Smart Care scan, switch to Projects and back | Scan keeps running, state preserved | |
| 10.2 | Start a scan, quit the app | Quits immediately, no hang | |
| 10.3 | Resize the window to the minimum | Sidebar labels stay readable, action bar stays usable | |
| 10.4 | Activity Monitor while idle on the results screen | CPU under 2 % | |
