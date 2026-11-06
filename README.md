# EasyHiDPI

A menu bar panel for external displays: switch HiDPI sizes and refresh rates, set brightness, manage display
override plists.

```bash
./scripts/rebuild-dev.sh
swift test
./scripts/release.sh
swift run EasyHiDPI --list
```

`rebuild-dev.sh` installs a debug build to `/Applications` and launches it. `release.sh` tests, signs,
notarizes, builds `dist/EasyHiDPI-<version>.dmg` and installs the notarized app. `--list` prints what the
panel would show, plus each display's negotiated link and EDID: the first thing to read when a display is
stuck at a low refresh rate.

`release.sh` reads `CODESIGN_IDENTITY`, and optionally `SIGNING_KEYCHAIN` and `NOTARY_KEYCHAIN_PROFILE`, from the
environment or an untracked `scripts/local.env`.

Overrides live in `/Library/Displays/Contents/Resources/Overrides`. New sizes appear after reconnecting the
display, and stay dashed in the panel until then.
