# yeet

`yeet` scans for removable USB drives and lets you eject one or more at once with a gum multi‑select UI. It shows a friendly volume/device name alongside the raw device path, then safely ejects via `diskutil eject` on macOS or `udisksctl power-off`/`eject` on Linux.

## Usage

```bash
yeet   # select one or more drives to eject
```

## Notes

- On Linux, `udisksctl` is preferred; `eject` is used as a fallback.

