# Astra Preview Templates

Modify `~/.config/astra/plugins/` to override previews for custom formats.

Example snippet:

```bash
on_preview() {
  local path="$1"
  case "$path" in
    *.log)
      tail -n 200 "$path"
      return 0
      ;;
  esac
  return 1
}
```
