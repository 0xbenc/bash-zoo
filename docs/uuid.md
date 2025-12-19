# uuid

`uuid` prints a fresh RFC 4122 v4 identifier and copies it to your clipboard so you can paste immediately into logs or dashboards. It prefers `uuidgen` when available, falls back to `/proc/sys/kernel/random/uuid` on Linux, and finally to Python 3’s `uuid` module.

## Examples

```bash
uuid               # prints and copies a v4 UUID
uuid | tee /dev/tty | pbcopy   # macOS: alternative copy path
```

## Platform Note

- The script works on macOS and Linux. The guided installer currently provisions it on Debian/Ubuntu; on macOS you can still use it by running it directly from `scripts/uuid.sh` or adding your own alias.

