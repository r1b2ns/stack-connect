# Logging

StackConnect writes to the unified log (`os.Logger`) under one subsystem, the
app's bundle identifier: `zeroSixteen.stackconnect`.

| Category | Written by |
| --- | --- |
| `UI` | the app itself (`Log.print`), e.g. `[GooglePlay] Rust core error: …` |
| `core.<target>` | the Rust core's diagnostic sink, forwarded by `RustCoreLogger` |

## The core's diagnostic log

The Rust core (`stack-connect-core`, see its `docs/LOGGING.md`) reports what it
does through a process-wide `CoreLogger` sink: every HTTP request with its
status and duration, token exchanges and 401 retries, writes and their outcome,
and why a call failed, including calls refused **before** anything was sent
(`local validation failed: …; request not sent to Google`).

`CoreLoggerInstaller.shared.install()` hands `RustCoreLogger`
(`StackConnect/Infra/Logging/RustCoreLogger.swift`) to the core at the start of
`StackConnectApp.init`, before any account connects. It is installed once per
process; later calls are no-ops.

- **Minimum level:** `debug` in DEBUG builds, `info` in Release (no per-request
  lines in production).
- **Categories:** `core.` + the core's target: `core.http`, `core.auth`,
  `core.googleplay`, `core.googleplay.users`, `core.googleplay.edits`,
  `core.googleplay.tracks`, `core.googleplay.reviews`,
  `core.googleplay.icons`, `core.appstore`.
- **Levels:**

  | Core level | Unified log type | Typical lines |
  | --- | --- | --- |
  | `error` | Error | HTTP 5xx, transport failures |
  | `warn` | Default (notice) | HTTP 4xx, local validation failures, failed cleanups |
  | `info` | Info | writes and their outcome, list totals, 401 retries |
  | `debug` | Debug | one line per request, paging, token minting |

  `warn` is not logged with `Logger.warning`, which the unified log records as
  an Error: a refused request would then look like a broken one.
- **Privacy:** lines are logged `privacy: .public`, so they are readable
  outside Xcode. The core redacts every line first: no access token,
  `Authorization` header, private key, JSON key or JWT, and user e-mails masked
  (`d***@agency.example`). Google's own error text is kept verbatim.

In the fake data mode (`-StackFakeData YES`) the fakes replace the core's
network layer, so few or no `core.*` lines appear; the app's own `UI` lines
(e.g. `[GooglePlay] Rust core error: …`) still do.

## Reading the logs

### Simulator or a Mac

Stream the core's lines live (Terminal):

```bash
log stream --predicate 'subsystem == "zeroSixteen.stackconnect" AND category BEGINSWITH "core."' --level debug
```

For a simulator, run it inside the simulator (replace `booted` with a UDID when
several are booted), or read the last minutes back:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "zeroSixteen.stackconnect" AND category BEGINSWITH "core."' --level debug
xcrun simctl spawn booted log show --last 5m --info --debug --predicate 'subsystem == "zeroSixteen.stackconnect" AND category BEGINSWITH "core."'
```

Drop the `category` clause to see the app's own lines too
(`subsystem == "zeroSixteen.stackconnect"`).

### An iPhone connected to this Mac (Terminal)

`scripts/device-logs.sh` streams the app's lines from a connected iPhone
(USB, or Wi-Fi for a paired device) through
[pymobiledevice3](https://github.com/doronz88/pymobiledevice3), filtered by
subsystem and category:

```bash
brew install pipx && pipx install pymobiledevice3   # once
scripts/device-logs.sh --device "iPhone name"       # core.* lines only
scripts/device-logs.sh --device "iPhone name" --all # app (UI) + core.* lines
scripts/device-logs.sh --category 'core.googleplay*' --save /tmp/stack.log
```

Unlock the iPhone and accept "Trust This Computer" the first time. A Debug
build (run from Xcode) logs `debug` lines, one per HTTP request; a Release
build (TestFlight / App Store) only `info` and above. Values logged as
private show as `<private>` on a device; the core's lines and the
`Rust core error` lines are public. Run `scripts/device-logs.sh --help` for
every option.

### Console.app (device or simulator)

1. Open Console.app and select the device (a connected iPhone) or the Mac
   running the simulator in the sidebar.
2. Choose **Action › Include Info Messages** and **Include Debug Messages**.
3. Press **Start**, then search `subsystem:zeroSixteen.stackconnect` and add
   `category:core.` (or a single target, e.g. `category:core.googleplay.users`).

### A tester's device (sysdiagnose)

When the problem happened on someone else's iPhone:

1. Reproduce the problem, then trigger a sysdiagnose right away: press and
   release **both volume buttons and the side button** together (hold about a
   second; a short vibration confirms). It takes a few minutes to collect.
2. Find it in **Settings › Privacy & Security › Analytics & Improvements ›
   Analytics Data**, named `sysdiagnose_…`, and share it (AirDrop, Files).
3. On a Mac, unpack it and open `system_logs.logarchive` in Console.app, or
   query it with the same predicate:

   ```bash
   log show system_logs.logarchive --info --debug --predicate 'subsystem == "zeroSixteen.stackconnect" AND category BEGINSWITH "core."'
   ```

Release builds deliver `error`, `warn` and `info` lines. The unified log keeps
Error and Default lines on disk; Info lines live in memory and may be gone
by the time a sysdiagnose is taken, so take it right after the problem.
