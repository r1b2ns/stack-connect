# Security Policy

StackConnect stores credentials that can manage apps and ship builds (App Store Connect API keys, Firebase service accounts), so security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub instead:

1. Go to the [Security tab](https://github.com/r1b2ns/stack-connect/security) of this repository.
2. Click **Report a vulnerability** (or open the [private report form](https://github.com/r1b2ns/stack-connect/security/advisories/new) directly).
3. Describe the issue, the affected version, and the steps to reproduce it.

You can expect a first reply within 7 days. Once the issue is confirmed, a fix is prepared in a private fork, released, and then disclosed in a security advisory that credits you, unless you'd rather stay anonymous.

Vulnerabilities in the Rust core can be reported the same way in [stack-connect-core](https://github.com/r1b2ns/stack-connect-core/security).

## Supported versions

Fixes go into `master` and ship in the next App Store release. Only the latest App Store version is supported.

## Scope

Examples of what is in scope:

- Credentials leaving the device other than to Apple's or Google's APIs, or being written outside the Keychain.
- Weaknesses in the encrypted account export (`.scexport`) format or its import.
- Secrets that are not masked in Network Audit, logs, analytics or crash reports.
- Ways for another app or a crafted file or URL to read or change StackConnect's data.

Out of scope: problems that need a jailbroken or already compromised device, and issues in Apple's or Google's services themselves (report those to Apple or Google).
