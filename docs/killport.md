# killport

`killport` frees a TCP or UDP port by discovering listeners, letting you select them with a gum UI, and sending a gentle `TERM` followed by an optional `KILL` after a short grace. It never escalates privileges and defaults to your own processes only.

## Usage

```bash
killport 3000                      # interactive select + confirm (TCP)
killport 5353 --udp --all --yes    # target all UDP listeners non-interactively
killport 8080 --list               # list found processes without acting
```

## Notes

- gum-only UI. On Linux, prefers `ss` if available; otherwise uses `lsof`.
- Safe defaults: TERM → optional KILL after 3s; wait up to 5s for the port to free; never sudo.

