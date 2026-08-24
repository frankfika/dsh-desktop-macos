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
