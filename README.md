# blocked-sites-in-south-korea

Offline-reviewed porn blocklist plus a macOS kill-switch blocker.

This repo intentionally does not open, search, or fetch the listed domains. The
review step normalizes `list.txt` and `kr.list`, removes clearly non-porn or
mixed/general-purpose domains from `allowlist.txt`, and writes the usable
blocklist to `reviewed/porn-blocklist.txt`.

## Review The List

```sh
./blockctl.sh build
```

Outputs:

- `reviewed/porn-blocklist.txt`: domains that will be blocked
- `reviewed/excluded-non-porn.txt`: excluded non-porn or mixed-purpose domains
- `reviewed/manual-review.txt`: kept domains with weak name-level adult signals
- `reviewed/review-report.md`: counts and exclusion summary

## Enable System-Wide Blocking

```sh
sudo ./blockctl.sh enable
```

This adds a marked block to `/etc/hosts`, including each domain plus common
`www.` and `m.` variants, then flushes macOS DNS caches. It applies across apps
that use the system resolver. If a blocked result appears in a search engine,
opening that result is denied by the host block; the search-results page itself
is not filtered.

## Strict Mode

```sh
sudo ./blockctl.sh strict-enable
```

Strict mode combines the local `/etc/hosts` block with Cloudflare Family DNS on
every macOS network service. Cloudflare Family DNS blocks malware and adult
content while keeping general-purpose sites such as Reddit resolvable.

The first strict-mode enable saves the previous DNS settings to:

```text
/Library/Application Support/porn-site-guard/dns-state.tsv
```

## Kill Switch

```sh
sudo ./blockctl.sh disable
```

The disable command removes only the marked block added by this tool and flushes
DNS caches.

For strict mode, use:

```sh
sudo ./blockctl.sh strict-disable
```

That removes the hosts block and restores the saved DNS settings.

## Status

```sh
./blockctl.sh status
```

Check a single domain without opening it:

```sh
./blockctl.sh check pornhat.one
```

## Strictness Notes

`/etc/hosts` blocking is system-wide, browser-independent, and easy to reverse,
but it cannot wildcard every possible subdomain and can be bypassed by VPNs,
private relays, or browser DNS-over-HTTPS configurations. Strict mode is stronger
because it adds DNS category filtering and SafeSearch enforcement, but it still
depends on browsers using system DNS.

For maximum strictness:

- Disable browser DNS-over-HTTPS.
- Disable VPNs and iCloud Private Relay while relying on this block.
- Block or avoid search engines that cannot be forced into SafeSearch.
- Keep the kill switch command available for intentional temporary access.

The next stronger version would be a small local DNS sinkhole or macOS Network
Extension content filter. That would support wildcard subdomain blocking and
harder bypass protection, but it is more invasive than a hosts-file guard.

No safe local tool can guarantee removal of every explicit result from every
search-results page in every browser without decrypting and rewriting HTTPS
traffic. The practical strict design is: force SafeSearch where supported, block
unsupported search routes, and deny navigation to adult domains at DNS or network
filter level.

See [docs/strict-mode-design.md](docs/strict-mode-design.md) for the full
strictness model.
