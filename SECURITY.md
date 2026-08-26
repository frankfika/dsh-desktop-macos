# Security policy

## Reporting a vulnerability

Please do not open a public issue for an unpatched vulnerability. Send a private report
to `chenpitang2020@gmail.com` with the affected version, reproduction steps, and impact.
You should receive an acknowledgement within seven days.

Vulnerabilities in the DeepSeek Harness runtime should be reported to the
[upstream project](https://github.com/deepseek-ai/deepseek-harness/security).

## Scope

DSH Desktop launches a local executable selected by the user and embeds its loopback Web
UI. It does not collect telemetry or own model credentials. Users should verify that the
selected executable comes from the official `@deepseek-ai/dsh` npm package and should not
expose the local Web service directly to an untrusted network.

## Mobile remote access

The optional macOS mobile bridge listens on the local network, while the DSH runtime remains
bound to loopback. Every dashboard, control API, HTTP proxy, and WebSocket upgrade requires a
random pairing token stored in an HttpOnly, SameSite cookie. Reset pairing in DSH Desktop if
a phone or QR link is lost.

The bridge deliberately uses plain HTTP so it works without certificate installation on a
home LAN. Use it only on a network you trust. For remote access over the internet, use an
encrypted private overlay such as Tailscale. Never expose the bridge port with router port
forwarding or a public tunnel that lacks its own TLS and access control.
