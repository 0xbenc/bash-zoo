# zapper

`zapper` prepares new entries for `zapp` by validating the payload, creating a `zapp.md` pointing to the chosen executable, and writing a `.desktop` file so the app shows up in your launcher with an icon.

## Examples

```bash
zapper ~/Downloads/Foo.AppImage
zapper ~/Downloads/bar-1.2.3-linux-x64.tar.gz
```

## What It Does

- Moves or extracts the payload into `~/zapps/<name>`
- Detects (or lets you choose) the main executable; records it in `zapp.md`
- Scans for icons near the executable and writes `~/.local/share/applications/zapp-<name>.desktop`

