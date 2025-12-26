# passage

`passage` is an interactive browser for your GNU Pass store. It lists entries with search, supports favorites (pins) and MRU ordering, and uses a simple text menu (no fzf). It also includes built‑in TOTP for entries that store a sibling `mfa` secret. You can:

- Copy the password (first line) directly.
- Reveal the password on screen until you clear it (also copies to clipboard).
- Toggle pin on an entry; pinned entries sort first.
- Start directly in MFA-only view with `passage mfa`.
- Start with an initial filter by passing arguments: `passage github` or `passage mfa github`.

## Notes

- Requires `pass` and a clipboard adapter (`pbcopy`, `wl-copy`, `xclip`, or `xsel`). For TOTP actions, install `oathtool`.
- Built‑in TOTP: entries ending in `/mfa` (or with a sibling `…/mfa`) expose OTP actions. Use `tN`/`Nt` to show the current code (also copies). Press `m` to toggle an MFA‑only view.
- Safe defaults: no secrets printed unless you choose Reveal.
- Commands:
  - Type a number to select an entry; then choose an action (Enter copies by default).
  - `cN` or `Nc` copy entry `N`. `rN` or `Nr` reveal entry `N` (also copies). `tN` or `Nt` show a TOTP for entry `N` when available (also copies). `pN` or `Np` pin/unpin entry `N`.
  - `m` toggles an MFA‑only view (shows only entries with `/mfa`).
  - `/term` filter list by substring; empty filter shows all again.
  - `O` via Options menu clears pins; `R` via Options menu clears recents.
  - `x` clears clipboard; `o` opens options; `q` quits.

## MFA Setup

Passage’s built‑in TOTP support uses the same `/mfa` convention as the former `mfa` helper. To make MFA work smoothly you need:

1. **Dependencies** — Install `pass`, `oathtool`, and your platform clipboard helper (`pbcopy` on macOS, `xclip`/`xsel` on Debian).
2. **Initialize pass** — Generate (or reuse) a GPG key, then run `pass init <gpg-id>`. This creates `~/.password-store` as your encrypted vault.
3. **Store MFA secrets** — Create an entry for each service that ends in `/mfa`. The entry must contain a single-line base32 secret (no URIs, no extra lines). For example:

   ```bash
   export PASSWORD_STORE_DIR=~/.password-store  # optional if using the default
   pass insert work/github/mfa                  # paste base32 secret on one line
   ```

   Paste the raw base32 TOTP secret when prompted (single line). The file lands at `~/.password-store/work/github/mfa.gpg`.
4. **Sync across devices (optional)** — If you use git to sync your password store, commit the new entry so other machines can see it. Passage respects `PASSWORD_STORE_DIR` if you keep the store somewhere else.

Once the store contains at least one `*/mfa` entry, run `passage mfa` to start directly in an MFA-only view, fuzzy-search the account, and copy the current 6‑digit code.

Security note: Passage never passes your secret as a command argument. It reads the single-line secret from `pass` and feeds it to `oathtool` via stdin to avoid exposure in process listings.
