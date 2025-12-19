# hostshelper

`hostshelper` keeps host/IP pairs and named presets in `~/.bash-zoo/hosthelper.toml`, then writes them into a managed block inside `/etc/hosts` with a gum UI. Add entries one field at a time, merge a single host into the block, or swap the block to a preset like `at-home`.

## Usage

```bash
hostshelper   # gum TUI for adding hosts, building presets, and applying to /etc/hosts
```

## Notes

- Gum-only UI; writing to `/etc/hosts` prompts for sudo.
- Managed block is wrapped with `# hostshelper start/end` and de-duplicates hostnames.
- Applying a preset replaces the managed block; applying a single host merges with the current block.

