# BAVtrix

Matrix digital rain for the desktop: a modern re-implementation of the classic
[ZMatrix](http://zmatrix.n3.net) for high-DPI and multi-monitor Windows, in the style of the
original (Matrix Code Font, the same `default.cfg` format, five settings tabs).

Матричный дождь для рабочего стола: современная версия ZMatrix для больших разрешений,
масштабирования DPI и нескольких мониторов.

## Status

| Platform | State |
|----------|-------|
| Windows 10/11 | Released (1.0): desktop layer, screensaver, installer with autostart |
| macOS | Planned |
| iOS | Planned (in-app rain; iOS has no API for home-screen wallpapers) |

## Windows

- Desktop mode: the rain is drawn between the wallpaper and the windows, hides the desktop icons
  and reveals only hovered or selected ones. The wallpaper shows through the glyphs.
- Screensaver (`bavtrix.scr /s`) and a settings window (`bavtrix.exe /c` or tray icon).
- Per-monitor DPI, several monitors, `default.cfg` compatible with ZMatrix plus a few extra keys
  (`SpawnRate`, `Flicker`, `HeadFlicker`, `HeadBrightness`, `TrailMin`, `TrailMax`).
- Setup program with a choice of install folder, autostart and shortcuts; per-user, no admin rights.

### Build

Rust (stable, `x86_64-pc-windows-gnu` or MSVC toolchain):

```
cd bmatrix
cargo build --release          # bavtrix.exe
```

The installer embeds the release files, so build the app first and put `bavtrix.exe`,
`README.txt` and `LICENSE.TXT` into `release/1.0/`, then:

```
cd installer
cargo build --release          # bavtrix-setup.exe
```

## Layout

- `bmatrix/` — the Windows application (Rust, Win32 via `windows-sys`)
- `installer/` — the Windows setup / uninstall program

## License

GPL-2.0-or-later (see `LICENSE`). Idea and config format: ZMatrix by Z. Shaker.
The bundled Matrix Code Font is freeware by e-RBi.

Author: BArkVestan_Development.
