# Strict Porn Blocking Design

The practical goal is to deny navigation to porn domains across the Mac and
reduce explicit search-result exposure across browsers.

## What This Repo Implements

1. Offline review:
   - Normalize `list.txt` and `kr.list`.
   - Exclude clearly non-porn or mixed/general-purpose domains via
     `allowlist.txt`.
   - Generate `reviewed/porn-blocklist.txt`.

2. Hosts block:
   - Add reviewed domains to `/etc/hosts`.
   - Include bare, `www.`, and `m.` variants.
   - Provide a kill switch that removes only this repo's marked block.

3. Strict DNS mode:
   - Keep the local hosts block.
   - Set macOS network services to Cloudflare Family DNS:
     `1.1.1.3`, `1.0.0.3`, `2606:4700:4700::1113`,
     `2606:4700:4700::1003`.
   - Save previous DNS settings before changing them.
   - Restore the saved DNS settings with `strict-disable`.

## Why DNS Filtering Is The Best Next Step

DNS filtering works before the browser connects to the destination, so it applies
across browsers and apps that use the system resolver. Cloudflare Family DNS
blocks malware and adult content without blocking general-purpose social/forum
domains like Reddit.

Official references:

- Cloudflare 1.1.1.1 for Families: https://one.one.one.one/family/
- CleanBrowsing Family Filter: https://cleanbrowsing.org/filters/
- Google SafeSearch VIP: https://support.google.com/websearch/answer/186669
- Bing strict SafeSearch DNS mapping:
  https://support.microsoft.com/en-us/bing/blocking-explicit-content-with-safesearch
- Apple Screen Time adult website limits:
  https://support.apple.com/guide/mac-help/change-app-store-media-web-games-settings-mchlbcf0dfe2/mac

## What Cannot Be Guaranteed Locally

No local hosts-file or DNS tool can guarantee that every explicit result
disappears from every search-results page in every browser, because search
results are delivered over HTTPS by the search engine itself.

To literally remove or rewrite arbitrary explicit results inside HTTPS pages, a
tool would need to decrypt and inspect browser traffic. That means installing a
trusted root certificate and running a local HTTPS filtering proxy or macOS
Network Extension content filter. That is more invasive, easier to break, and
creates privacy/security risk.

## Strongest Reasonable Setup

Use layers:

1. `sudo ./blockctl.sh strict-enable`
2. Disable browser DNS-over-HTTPS or configure it to use Cloudflare Family DoH.
3. Turn on macOS Screen Time's `Limit Adult Websites` as a second local layer.
4. Disable VPNs, iCloud Private Relay, and proxy extensions while relying on the
   block.
5. Prefer search engines that support forced SafeSearch. Block engines that do
   not provide enforceable SafeSearch.

This does not make bypass impossible for an administrator account, but it is the
best low-maintenance setup that avoids decrypting all browser traffic.
