# zapp

`zapp` launches AppImages or unpacked Linux apps staged under `~/zapps`. It lists available apps, accepts a single‑letter selection, and runs the best match inside the chosen folder:

1) `zapp.AppImage` if present and executable
2) The executable path named in `zapp.md`
3) Otherwise, it prompts you to pick from detected executables in the folder (or its single subfolder)

## Example

```bash
zapp   # interactive launcher; pick by letter
```

