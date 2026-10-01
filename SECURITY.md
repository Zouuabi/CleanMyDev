# Security and safety

CleanMyDev deletes files, reads your whole home folder, talks to the Docker daemon, and (optionally) writes to the SMC. Here is exactly what that means.

## What it never does

- Sends data anywhere. There is no analytics, crash reporter, or update check. The only network call is the optional menu-bar speed test, which downloads random bytes from `speed.cloudflare.com` and uploads random bytes back.
- Deletes outside the rules. `SafetyGuard` refuses `/System`, `/usr`, `/bin`, `/sbin`, `/Library/Apple`, `/private/var/db`, your never-touch folders, and anything inside an Active or Pinned project, after resolving symlinks.
- Deletes database data, VM disks, Keychains, SSH keys, or app data of running apps. Those are shown with a lock and `removal: .never`.
- Runs anything as root without asking. Fan control re-executes the app with administrator privileges for one SMC write and exits; macOS shows its own password prompt each time.

## What it needs and why

| Permission | Why |
|---|---|
| Full Disk Access | To see Mail, Safari, Containers, and parts of `~/Library`. Without it macOS hides them and the app would both miss junk and, worse, block on consent dialogs mid-scan. The app refuses to start without it. |
| Administrator password (fan control only) | SMC writes need root. |
| Docker socket | Via the `docker` CLI you already have; read-only until you clean an image or volume. |

## Defaults that protect you

- Cleaning goes to **Quarantine** (restorable for 7 days) unless you choose Trash or permanent.
- Projects touched in the last 14 days, with running containers, a dev server, or an open shell are **Active**: nothing inside them is offered.
- Docker images are review-only: a hand-built image has no label tying it to a project, so you decide.
- Every action is logged to `~/Library/Logs/CleanMyDev/operations.log`.

## Reporting

If you believe the app deleted something it should not have, or you found a way to make it do so, open a GitHub issue with the log lines involved. For anything you'd rather not post publicly, use GitHub's private vulnerability reporting on the repository.
