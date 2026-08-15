# DiskSize

A small native macOS app to see **what's using space on disk** for a folder or file — the GUI equivalent of:

```sh
du -h -d1 ~/some/folder
```

…and to **permanently delete** a folder (`rm -rf`) right from the results, with a confirmation.

## What it does

- Pick a folder or file (or type/paste a path).
- See the **total size** plus every immediate child, sorted largest-first, with a proportion bar.
- **Scans once, then browses instantly.** One `du -k <path>` (no depth limit) walks the whole subtree and records the size of *every* directory in it — for the same disk cost as a one-level scan, since `du` traverses everything regardless. Those sizes are kept in an **index**, so drilling into any subfolder or going back up is served from cache with no re-scan. The header shows a ⚡️ "Indexed …" / 🕓 "Scanned …" badge with the scan time.
- **The index persists across launches.** It's saved to `~/Library/Application Support/DiskSize/` (one JSON file per scanned root, plus a small manifest). Re-open the app and re-visit a folder you've scanned before and it appears **instantly** from disk — no waiting for a scan.
- **Incremental refresh.** After showing the cached result, a background pass stats every indexed directory's modification date, finds the ones that changed, re-`du`s only those (the minimal changed subtrees), and propagates the size deltas up their parents. Unchanged subtrees are never re-walked. The header shows "refreshing changed folders…" while this runs.
- **Cache invalidation:** *Rescan* discards the index and scans fresh; deleting anything rebuilds it; and if a folder's modification date is newer than the scan, the header flags "changed since scan" with a one-click Rescan.
- Sizes come from `du -k` and are formatted to human units (KB/MB/GB) in-app, so sorting stays accurate. Individual file sizes come straight from the filesystem (`stat`) — no recursion needed.
- **Permission-denied paths** (e.g. system folders): the app shows a banner and a one-click **"As Admin"** rescan that triggers the standard macOS admin-password prompt.
- **Delete**: the trash button asks for confirmation (showing the full path + size), then lets you **Move to Trash** (reversible, the safe default) or **Delete Permanently** with `rm -rf`. There's an **admin** variant of the permanent delete for protected paths, and a hard guardrail that refuses `/`, your home folder, and top-level system directories.

## Requirements

- macOS 14 or later
- **Full Xcode** (not just Command Line Tools) to build/run

## Build & run

```sh
open DiskSize.xcodeproj
```

Then press **⌘R** in Xcode.

The app runs **without the App Sandbox** (see `DiskSize/DiskSize.entitlements`) because it execs `du`, `rm`, and `osascript` on arbitrary user-chosen paths. It's a local power-tool, not a Mac App Store submission. Xcode signs it "to run locally" — no developer account needed.

## Layout

```
DiskSize/
  DiskSizeApp.swift          # @main entry
  ContentView.swift          # the UI + view model
  Models/DiskItem.swift      # one row: url, byteSize, isDirectory
  Services/Shell.swift       # Process runner + admin escalation + quoting
  Services/DiskScanner.swift # builds/parses `du -k -d1`
  Services/Deleter.swift     # rm -rf (user + admin) with guardrails
```

## Known limitation of incremental refresh

Incremental refresh detects change by directory modification dates. A directory's
mtime moves when an entry is **added, removed, or renamed** — but *not* when an
existing file's contents change in place. So if a file grows without any directory
entry changing, the incremental pass can miss it until you hit **Rescan** (a full
`du`, which is always ground truth). This is the standard trade-off incremental
scanners make in exchange for not re-walking the whole tree every time.

## Safety notes

**Move to Trash** is reversible — items go to the Finder Trash and can be restored. **Delete Permanently** (`rm -rf`) does **not** use the Trash and cannot be undone. Either way, the confirmation dialog always names the exact path and its size before anything is removed.
