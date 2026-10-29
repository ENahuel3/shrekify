# Shrekify

A reversible Windows desktop prank. Run it once and your wallpaper, the images
in your Desktop/Pictures folders, and your shortcut icons all become Shrek. Run
it a second time and everything goes back to exactly how it was.

> It's a **toggle**: a backup manifest decides the direction, so you never have
> to remember which state you're in.

## How it works

Nothing is ever deleted. Originals are **moved** into
`%LOCALAPPDATA%\Shrekify\backup` and recorded in `manifest.json`. Restoring
moves them back and clears the manifest.

| Target | Shrekify | Restore |
|---|---|---|
| Wallpaper | saved from registry, swapped for `shrek.jpg` | set back |
| Images in target folders | moved to backup, replaced with `shrek.jpg` | moved back |
| Shortcut (`.lnk`) icons | repointed to `shrek.ico` | repointed back |

## Usage

```powershell
# Put shrek.jpg (and optionally shrek.ico) next to the script, then:
powershell -ExecutionPolicy Bypass -File .\Shrekify.ps1          # shrekify
powershell -ExecutionPolicy Bypass -File .\Shrekify.ps1          # run again -> restore

powershell -File .\Shrekify.ps1 -WhatIf                          # preview, change nothing
powershell -File .\Shrekify.ps1 -Folders 'C:\Users\me\Demo'      # custom folders
powershell -File .\Shrekify.ps1 -AllDrives                       # whole drives (see warning)
```

## Deliberate safety limits

- **Not the whole OS.** By default only your Desktop and Pictures. `Windows`,
  `Program Files`, and app data are always skipped, even with `-AllDrives` —
  overwriting images there breaks applications.
- **Shortcut icons, not `.exe` icons.** Rewriting icons embedded inside program
  binaries breaks their code signatures and looks like malware to antivirus, so
  this only retargets `.lnk` shortcuts.
- **Reversible by design.** Originals are preserved, not destroyed. Keep the
  `%LOCALAPPDATA%\Shrekify` folder until you've restored.

Run it on your own machine (or one you're authorized to prank). Not for
deploying to other people's computers without consent.
