# ssherpa

`ssherpa` scans your `~/.ssh/config` and any `Include`d files, lists your Host entries, and lets you fuzzy-pick one with gum to connect. By default it hides pattern hosts (those with `*` or `?`), but you can include them with `--all`. It also includes an interactive “Add new alias…” flow to create or update Host stanzas in your config (atomic write, no sudo).

## Usage

```bash
ssherpa                          # pick and connect (always offers “Add new alias…”)
ssherpa --print -- -L 8080:localhost:8080    # print the ssh command
ssherpa --filter prod --user alice            # prefilter by text and user
ssherpa --all                                 # include wildcard patterns too
```

## Notes

- Gum-only UI; no fzf. It parses `Host`, `HostName`, `User`, `Port`, and first `IdentityFile`. `Match` blocks are ignored.
- Labels show `user@host:port [key]` when present; connection is always `ssh <alias>` so your config fully applies.
- Entries with `User git` are hidden by default; set `SSHERPA_IGNORE_USER_GIT=0` in your shell config to include them.

