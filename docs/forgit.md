# forgit

`forgit` sweeps the directories beneath your current working tree and flags every Git repository with uncommitted changes or pending pushes. It also shows the current branch for each flagged repository so you can jump directly to the right place. Use it as a morning ritual to catch forgotten work: run `forgit` from `~/code` (or similar) and drill into repositories that show up with red or yellow markers. The script respects Git status output, so clean repos never clutter the list.

## Usage

```bash
forgit                       # audit every git repo under the current directory
forgit ~/code                # audit a specific path
forgit --timeout-secs 5      # per-repo remote check timeout (default: 10s)
FORGIT_NO_NETWORK=1 forgit   # skip remote checks (no network)
```

## Notes

- The timeout applies to remote checks and helps skip slow/hung remotes.

