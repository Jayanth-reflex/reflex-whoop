# ReflexWhoop

An iPhone app that keeps your WHOOP data on your phone, measures each reading against
your own normal, and keeps working if your membership ends.

It pulls your history from the WHOOP API, records live heart rate straight from a
WHOOP 5.0 band over read-only Bluetooth, and stores both in a local SQLite archive it
never deletes. A small MCP server lets Claude on your Mac query an exported copy.

> **Unofficial.** Not affiliated with, endorsed by or supported by WHOOP. The
> Bluetooth protocol is reverse-engineered. This is not a medical device, and nothing
> it shows is medical advice.

## What it does

- **Today:** recovery with a one-sentence verdict, strain on WHOOP's 0–21 scale, last
  night's sleep, and overnight vitals (HRV, resting heart rate, breathing rate, skin
  temperature, blood oxygen), each against your 60-day normal.
- **Trends:** every metric over 30 days, 90 days, a year or all history. **Patterns**
  tests which habits track next-morning recovery, with multiple-comparison correction
  and an honest "not enough data yet". **Unusual days** lists readings 2 SD or more
  from normal and flags nights when several signals move together.
- **Band:** live heart rate and recordings from the band, kept going in the background
  with **Keep recording**.
- **Archive:** what the phone holds, source status, export (CSV, a SQLite snapshot and
  raw payloads), and Celsius or Fahrenheit.

## Safety and privacy

- **The band is never modified.** Every Bluetooth command passes a compile-time
  allowlist of read-only and live-stream opcodes. Commands that read or move the band's
  stored history, change its clock or reboot it can't be sent, and history packets
  are never acknowledged. Details: [docs/PROTOCOL-GEN5.md](docs/PROTOCOL-GEN5.md#safety-rails).
- **Your data stays on the phone.** No server, no analytics. It leaves only when you
  export it.
- **Credentials stay in the Keychain.** You bring your own WHOOP developer app; its
  client ID and secret, and your tokens, are never in the binary or the repository.
- **Nothing is made up.** A missing reading shows as missing, never as zero.

## Requirements

- A Mac with Xcode 26 or later, and an iPhone on iOS 26 or later.
- An Apple ID signed into Xcode (Settings → Accounts). A free account works; its
  installs expire after 7 days and reinstalling loses nothing.
- For WHOOP data, an active WHOOP membership. For live heart rate, a WHOOP 5.0 band
  already paired with the official WHOOP app on the same iPhone.

## Setup

**1. Create a WHOOP developer app.** At [developer.whoop.com](https://developer.whoop.com),
create an app with redirect URI `reflexwhoop://oauth/callback` and all six scopes:
`read:profile`, `read:body_measurement`, `read:cycles`, `read:recovery`, `read:sleep`,
`read:workout`. Keep the client ID and secret for step 3.

**2. Build and install.**

```bash
git clone https://github.com/Jayanth-reflex/reflex-whoop.git
cd reflex-whoop
gem install --user-install xcodeproj
DEVELOPMENT_TEAM=YOUR_TEAM_ID BUNDLE_ID=com.yourname.reflexwhoop ruby scripts/generate_project.rb
open ReflexWhoop.xcodeproj
```

Your team ID is in Xcode → Settings → Accounts, or on the Apple Developer site. In
Xcode, pick your iPhone and press Run. The first time, trust your Apple ID on the
phone: Settings → General → VPN & Device Management.

**3. Connect.** The first-run flow asks which sources to use. For WHOOP, enter the
client ID and secret and sign in; the app then brings in your full history. For the
band, allow Bluetooth and turn on Keep recording.

## Ask Claude about your data

Export a copy from Archive, then point the MCP server at the snapshot. It opens the
database read-only. Setup: [mcp-server/README.md](mcp-server/README.md).

## Development

```bash
xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Swift, SwiftUI, Swift Charts and [GRDB](https://github.com/groue/GRDB.swift), with no
other app dependencies. Re-run `ruby scripts/generate_project.rb` after adding or removing
files. Contributors and coding agents: read [AGENTS.md](AGENTS.md) first.

| Doc | What's in it |
|---|---|
| [AGENTS.md](AGENTS.md) | commands, rules that must never break, conventions |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | sources, storage, sync, analysis, export, limits |
| [docs/PROTOCOL-GEN5.md](docs/PROTOCOL-GEN5.md) | the band's Bluetooth protocol, safety rails, findings |
| [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md) | colour, type, components, screens, copy rules |
| [docs/DECISIONS.md](docs/DECISIONS.md) | non-obvious choices and why |
| [docs/ADR-001-data-sovereignty.md](docs/ADR-001-data-sovereignty.md) | why the archive is source-neutral |

## Status and limits

Working: WHOOP sync with backfill and re-scoring, baselines, unusual days and illness
flags, correlations, live heart rate from the band, export, and the MCP server.

Not yet:

- **Heart rate is the only decoded band signal.** Beat-to-beat intervals, optical and
  motion data aren't decoded, so there's no HRV or breathing rate from the band.
- **Readiness is hidden.** The app's own readiness score relies on WHOOP's capped
  sleep-debt figure, so it stays off-screen until that's rebuilt
  ([why](docs/DECISIONS.md#readiness-hidden-until-sleep-debt-is-rebuilt)).
- **No widgets, iCloud or HealthKit.** They need paid-account capabilities.
- **Background recording can be interrupted.** iOS can suspend or end background apps.
- **A WHOOP firmware update can break decoding.** Raw bytes are always kept, so a fixed
  decoder can rebuild the history.
