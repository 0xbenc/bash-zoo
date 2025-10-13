# Astra Usage Guide

Astra is a terminal file manager built on Bash and fzf. This guide walks through the everyday keys and customization points.

## Launching

```bash
astra              # start in the current working directory
astra --debug      # verbose logging to help debug issues
astra --config /path/to/config.json
```

If `astra` is not in your PATH, run `./install.sh` from the repo, select Astra, then reload your shell (`exec $SHELL -l`).

By default Astra always opens in the directory you launch it from. To opt into restoring the last visited directory, set `"session": { "resume_last": true }` in your config (see below).

## Reading the UI

- **Left pane**: fzf list of entries in the current directory. Directories show as `[D] name/`, symlinks as `[L] name@`, the parent entry appears as `[↑] ..` when you are not at `/`.
- **Right pane**: live preview (text via bat, images via chafa/kitty, PDFs via pdftotext, archives/media via helper tools).
- **Bottom bar**: a nano-style shortcut strip fixed to the bottom of the terminal.
- **Header**: absolute working directory plus hidden-file state (`hidden:on|off`).

## Navigation

| Action                        | Keys                                  |
| ----------------------------- | ------------------------------------- |
| Descend into entry / open     | `Enter`, `→`, `l`                      |
| Go to parent directory        | `←`, `h`, or highlight `[↑] ..` + `Enter` |
| Toggle hidden files           | `.`                                   |
| Scroll list                   | `j`/`↓`, `k`/`↑`, `Ctrl-F`/`Ctrl-B` for pages |
| Search in current tree        | `Ctrl-G` (type pattern, hit Enter)     |
| Refresh (implicit)            | The list reloads after any action     |

## File Operations

| Operation             | Keys / Flow                             |
| --------------------- | --------------------------------------- |
| Edit in `$EDITOR`     | `Ctrl-E`                                 |
| Rename                | `Ctrl-R`                                 |
| Copy                  | `Ctrl-Y` (prompts for destination)       |
| Move                  | `Alt-M`                                  |
| Delete (to trash/rm)  | `Ctrl-D` (confirmation required)         |
| New directory         | `Ctrl-B`                                 |
| New file              | `Ctrl-N`                                 |
| Properties            | `Ctrl-P` (shows size, perms, mtime)      |

Selections honor multi-select in fzf: use **Space** to tag multiple rows, then trigger the action. If nothing is selected, the action targets the current row.

## Search

`Ctrl-G` prompts for a name fragment. Astra runs `fd`/`find` to collect matches, re-enters fzf on the result set, and applies the normal navigation rules (Enter to open, ← to go back, etc.).

For content search, use the command palette (upcoming) or run ripgrep manually until that feature lands.

## Configuration

- Config lives at `~/.config/astra/config.json`. It is auto-created from `astra/share/examples/config.json` on first run.
- Toggle defaults such as `browser.show_hidden`, theme selection, or history limits as needed.
- To resume where you left off between launches, set `session.resume_last` to `true`. Leave it at `false` (the default) to always honour the current shell directory.

## Tips

- Missing preview helpers (bat, chafa, pdftotext, ffprobe) show inline hints. Install using `setup/debian/astra.sh` or `setup/macos/astra.sh` for full fidelity.
- State (history, last directory) persists in `${XDG_STATE_HOME:-~/.local/state}/astra/state.json`. Delete it if you want a reset.
- Use `ASTRA_LOG_LEVEL=debug astra` when debugging key handling or preview issues.

Enjoy exploring — feedback on workflows or additional bindings is welcome.
