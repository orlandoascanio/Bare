# HideDesktop

Free and open-source macOS menu bar app that hides your Desktop icons. You can hide all of them or pick what goes: just folders, just screenshots, everything except apps, and so on.

On Windows this is right-click → View → Show desktop icons. On macOS people are charging money for it. Not here.

## Features

- **Click the menu bar icon to hide/show.** Double-click (or right-click) it to open the menu. Or use the global shortcut **⌃⌥⌘H** (Control-Option-Command-H) from anywhere.
- **Everything** in one click, or **Choose Types ▸** to pick exactly what goes, with a live count for each:
  - Folders
  - Screenshots & Recordings
  - Images & Photos
  - Videos & Audio
  - Documents (PDF, text, Office, Pages…)
  - Archives, DMGs & Installers
  - Apps & Aliases
  - Other Files
- **Quick picks** in the same submenu: Only Folders · Only Files · Only Screenshots · Only Photos/Screenshots/Videos · Everything except Apps.
- **Also Hide Disks & Servers** (uses Finder's own setting; Finder relaunches when this changes).
- **Auto-hide new items**: new screenshots and downloads disappear as soon as they land.
- Prefer a plain menu? Turn off **Click icon to hide** in Options and a single click opens the menu instead.
- **Launch at login**, and an option to **show everything again when quitting**.
- No Dock icon, no network access, no analytics, no accounts.

## Install

You need Xcode or the Xcode Command Line Tools (`xcode-select --install`). macOS 13 Ventura or newer.

```bash
git clone https://github.com/orlandoascanio/HideDesktop.git && cd HideDesktop
./build.sh --install
```

That builds `HideDesktop.app`, copies it to `/Applications` and launches it. Look for the 👁 icon in the menu bar. The first time it touches your Desktop, macOS asks for permission to access the Desktop folder. Click **Allow**.

To only build: `./build.sh` (the result goes in `build/HideDesktop.app`).

## How it works

HideDesktop sets the standard macOS **hidden** file flag on Desktop items, the same flag `chflags hidden` sets. Finder stops drawing them right away, with no restart.

- Files are **never moved, renamed or deleted**. They're still in `~/Desktop`, still in Finder sidebar searches, still openable from apps.
- It remembers exactly which items it hid, so "Show" only un-hides those. Anything you hid yourself stays hidden.
- Symlinks are hidden themselves; their targets are never touched.
- "Disks, Drives & Servers" flips Finder's `ShowHardDrivesOnDesktop`, `ShowExternalHardDrivesOnDesktop`, `ShowRemovableMediaOnDesktop` and `ShowMountedServersOnDesktop` settings. Your original values are saved and put back.

### Good to know

- If you've turned on "show hidden files" in Finder (⌘⇧.), hidden items show up dimmed on the Desktop too. Press ⌘⇧. again to turn it off.
- Works with iCloud "Desktop & Documents" folders.
- If you delete the app while icons are hidden, quit it first (with "Show icons again when quitting" on), or open the app once and choose **Show Desktop Icons**. As a last resort, `chflags nohidden ~/Desktop/*` un-hides everything (including items you hid yourself).

## Project layout

```
Sources/HideDesktop/
  main.swift          app entry point (menu bar only)
  AppDelegate.swift   status item, menu, actions, launch at login
  DesktopHider.swift  hide/show logic, Desktop watcher, drive settings
  Classifier.swift    decides which category a Desktop item belongs to
  Settings.swift      categories and saved preferences
  HotKey.swift        global ⌃⌥⌘H shortcut (no Accessibility permission needed)
Resources/Info.plist
build.sh
```

## License

MIT. Do whatever you want with it, just don't sell it back to people.
