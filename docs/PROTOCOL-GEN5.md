# WHOOP 5.0 (Gen 5) Bluetooth protocol

What ReflexWhoop knows about the WHOOP 5.0 band's Bluetooth protocol, how sure it is
of each fact, and the rails that keep the app from ever disturbing the band. WHOOP
publishes none of this. Everything marked confirmed was checked against raw frames
captured from a worn band and kept in `ingest_inbox`.

**Read [Safety rails](#safety-rails) before changing anything in `ReflexWhoop/Ble/`.**

## Safety rails

The band keeps a flash read cursor that is shared with the official WHOOP app and
persists across connections. Moving it could starve the official app and corrupt real
recovery and strain scores. So the app is **live-stream only and read-only by
construction**:

- **One choke point.** `OpcodeAllowlist.assertAllowed` runs on the opcode byte
  immediately before every `BandConnection.send`. Nothing else can originate a write.
  `OpcodeAllowlistTests` pins both tables below.
- **Forbidden opcodes can't be sent**, and no flag changes that. They're named only in
  `Ble.ForbiddenOpcode`, so the test can prove each one is rejected.
- **Never ACK history.** A `0x2F` or `0x31` packet is logged and never acknowledged,
  whatever the app thinks it asked for. No ACK, no cursor movement.
- **No write path to any band setting**, alarm or clock.
- **Only decode a field once captured frames confirm it.** Never fabricate a value.

Allowed:

| Opcode | Command | Why it's safe |
|---|---|---|
| `0x23` | `GET_HELLO_HARVARD` | read-only identity, battery, wrist |
| `0x1A` | `GET_BATTERY_LEVEL` | read-only (the standard `0x180F` battery characteristic always reports 100%) |
| `0x22` | `GET_DATA_RANGE` | read-only backlog window query; doesn't move the cursor |
| `0x03` | `TOGGLE_REALTIME_HR` | live stream toggle, no flash access |
| `0x3F` | `SEND_R10_R11_REALTIME` | live HR and IMU |
| `0x6A` | `TOGGLE_IMU_MODE` | live IMU |
| `0x6B` | `ENABLE_OPTICAL_DATA` | wrist-gated optical, live only |
| `0x6C` | `TOGGLE_OPTICAL_MODE` | live optical |

Permanently forbidden:

| Opcode | Command | Why |
|---|---|---|
| `0x16` | `SEND_HISTORICAL_DATA` | starts a flash drain |
| `0x17` | `HISTORICAL_DATA_RESULT` | the ACK that advances the shared cursor |
| `0x21` | `SET_READ_POINTER` | moves the shared cursor |
| `0x14` | `ABORT_HISTORICAL_TRANSMITS` | only meaningful while draining |
| `0x9A` | `TOGGLE_PERSISTENT_R21` | forces optical on and leaves the LED stuck on |
| `0x1D` | `REBOOT_STRAP` | hard reset |
| `0x0A` | `SET_CLOCK` | writes the band's real-time clock |

After any session that shows unusual band activity, open the official WHOOP app and
confirm it still syncs and its scores are intact. Every such check so far has passed.

## Connection

| | Gen 4 (published by OpenStrap) | **Gen 5 (WHOOP 5.0)** |
|---|---|---|
| Service | `61080001-8d6d-82b8-614a-1c8cb0f8dcc6` | **`fd4b0001-cce1-4033-93ce-002d5875f58a`** |
| Length check | CRC-8 | **CRC-16/MODBUS over the header** |
| Padding | inner padded to a multiple of 4 | **none** |
| Writes | either type | **write-with-response only; write-without-response is a no-op** |
| Extra characteristic | — | **`fd4b0007`** |

| Characteristic | Direction | Carries |
|---|---|---|
| `fd4b0002` | write | commands |
| `fd4b0003` | notify | command responses |
| `fd4b0004` | notify | events |
| `fd4b0005` | notify | data |
| `fd4b0007` | notify | CBOR device metadata, not envelope-framed |

**Bonding.** Gen 5 needs authenticated pairing. The phone already holds a bond from
the official WHOOP app, and CoreBluetooth reuses it; the official app can stay open.

**Writes are serialized.** `BandConnection.send` waits for `didWriteValueFor` (or a
3-second timeout) before the next write. Firing writes back-to-back lost the first
two commands ([session 3](#session-3-2026-09-07-a-write-ordering-bug)).

## Envelope (confirmed)

Verified by CRC on every one of 711 frames in session 1 and 7,343 in session 2, with
zero exceptions. Implemented in `Framing.swift` (`Gen5Envelope`).

```
byte 0      0xAA        marker
byte 1      0x01        version (constant so far)
bytes 2-3   u16 LE len  = innerLen + 4
bytes 4-5   u16 LE      field, constant 0x0001 so far; meaning unknown
bytes 6-7   u16 LE      CRC-16/MODBUS over bytes 0-5
bytes 8..   inner       [packet_type][seq][opcode | event_id | record_type][body…]
last 4      u32 LE      CRC-32 (IEEE 802.3) over the inner bytes only
```

Total frame length is `8 + innerLen + 4`, exactly.

**Reassembly is length-based, never triggered on `0xAA`.** Sensor payloads contain
`0xAA` constantly; resyncing on the marker is the most common way a decoder silently
corrupts data. `FrameReassembler` implements this but has never met a real fragmented
frame: every notification captured so far (largest inner payload 112 bytes) arrived
whole. R21 and r22 records are expected to fragment.

## Packet types

| `inner[0]` | Meaning | Confidence |
|---|---|---|
| `0x23` | command (outgoing) | confirmed |
| `0x24` | command response, and sometimes a carrier for firmware log text | confirmed as responses; see [session 4](#session-4-2026-09-07-firmware-log-strings) |
| `0x28` | realtime compact heart rate, ~1 Hz | **confirmed, decoded** |
| `0x2B` | R10 realtime raw (HR + IMU), per Gen 4 | never observed on Gen 5 |
| `0x2F` | general sensor-record wrapper, used by the connect-time catch-up burst and the live stream alike | high |
| `0x30` | event | consistent with Gen 4; few samples |
| `0x31` | sync marker | plausible from timing, not confirmed field by field |
| `0x32` | plain-ASCII firmware debug log lines | confirmed |
| `0x33` / `0x34` | IMU, per Gen 4 | never observed on Gen 5 |

### `0x28`: realtime compact heart rate (confirmed)

20-byte inner payload. Decoded by `RealtimeHRDecoder`, which reads `inner[8]` only.

```
inner[0]      0x28        packet_type
inner[1]      0x02        constant; subtype?
inner[2..3]   u16 LE      monotonic counter (not wall-clock time)
inner[4..5]   0x9e 0x6a   constant; unknown
inner[6..7]   varies      changes with the counter's rollover; unknown
inner[8]      u8          HEART RATE, bpm, unscaled
inner[9..19]  varies      unmapped (likely signal quality, motion, skin contact)
```

Physiologically plausible (65–95 bpm at rest and light activity) and stable across
three sessions on different days. Not yet cross-checked against the official app's
live heart rate.

### `fd4b0007`: device metadata (identified, not mapped)

About once per connection. Not envelope-framed. The bytes are CBOR; readable text
includes a version-like string (`50.41.1.0`), a hardware-like string (`WG50_r45`), a
codename (`maverick`) and a long ID. `DeviceMetadataDecoder` surfaces the strings for
Signal details without claiming which is which.

### `0x32`: firmware debug log

`inner[16:]` decoded as ASCII up to the first NUL gives literal firmware log lines,
for example:

```
BLE: hist transfer start response ack, start burst
BLE: History burst success. Trim: 0x00000002:0001c4e5 (2:115941)
BLE: Historical Dump Complete
BLE: Pull stats: Data: 598, Events: 27, Bytes: 77132, Secs: ...6.280
BLE_CMD: Invalid packet, error = 2
BLE_CMD: Command Get Data Range
```

## Not decoded yet

- **R10** (`0x2B`): never seen. `R10Decoder` is a speculative decoder that
  applies Gen 4's layout and calls a frame plausible only when heart rate and an
  accelerometer magnitude near 1 g both agree. R10 heart rate and `0x28` heart rate
  should agree within ±1 bpm on a worn band, a free cross-check that Signal details
  computes (labeled unconfirmed) once both exist.
- **R21**: six-channel optical, the only route to a true respiratory rate.
- **r22**: reportedly HR, RR intervals and accelerometer. The firmware names at least
  nine versions (`enable_r22_packets`, `enable_r22_v2_packets` … `v9`), and each enable
  attempt is followed by `SENSORS: No active sources. Backlog: 0.0`: a precondition
  (skin contact, wear time, something else) isn't met. No r22 frame has arrived.
- **Events**: Gen 4 numbering (`9` wrist on, `10` wrist off, `3` battery, `7`/`8`
  charging, `13` RTC lost, `14` double tap) is the hypothesis, not confirmed.

**Gen 4's type-24 layout, the hypothesis to test against:** `[7:11]` u32 LE unix time,
`[17]` u8 HR, `[18]` RR count, `[19:19+2n]` i16 LE RR ms, `[29]` u16 green PPG, `[31]`
u16 red/IR, `[36:48]` f32×3 accelerometer, `[51]` skin contact 0–198, `[64]`/`[66]`
red/IR ADC, `[68]` skin temperature ADC, `[70]` ambient light, `[88]` RHR baseline.

**How to hunt a field:** correlate a candidate heart-rate byte against the official
app's live number or a chest strap; find RR arrays as runs of plausible 600–1400 ms
i16 values; find the accelerometer as f32 triples with magnitude ≈ 1 g at rest.
`PacketTypeCounts` on Signal details shows when a new packet type first appears.

## Open questions

- Does `field` (bytes 4–5) ever differ from `0x0001`?
- `GET_HELLO_HARVARD` and `GET_BATTERY_LEVEL` have never been answered, while every
  one-byte-body command is. They now send a `0x00` body to test whether empty bodies
  are dropped ([session 5](#session-5-2026-09-12-a-clean-session)).
- The `0x24` response sequence number is the band's own persistent counter, not the
  app's, so it can't attribute a response to a request.

## Session log

### Session 1 (2026-09-07): envelope confirmed

711 frames, ~10 minutes. The envelope the original plan guessed (Gen 4 shape) was
wrong; brute-forcing checksum ranges over 14 near-identical frames found the layout
above, then it matched all 711. The app's four commands, built with the wrong
envelope, were all rejected by the band (`Invalid packet, error = 2`), so the app
changed nothing that session. A connect-time burst of 598 records and 27 events
(77 KB in ~4 s) appeared in the debug log; the app didn't command it. Official app
checked afterwards: synced normally, scores intact.

### Session 2 (2026-09-07): heart rate decoded

7,343 frames over three reconnects, ~92 minutes, every one with valid CRCs. Commands
now parsed. `0x28` identified as realtime heart rate (409 frames at 1 Hz) and
`fd4b0007` as CBOR. `0x2F` turned out to be the same 112-byte structure in the
catch-up burst and the live stream, so it is a general record wrapper, not a
drain-specific type. Official app checked: normal.

### Session 3 (2026-09-07): a write-ordering bug

First session with the IMU and optical toggles. The five toggles got responses;
HELLO and battery got none, because seven back-to-back writes lost the first two.
`BandConnection.send` now awaits each write's completion. No new packet type appeared
in 130 seconds.

### Session 4 (2026-09-07): firmware log strings

Firmware log text also rides inside `0x24` frames, so a `0x24`'s apparent opcode echo
can't be trusted as a response to the app. Recovered persistent config keys include
`enable_r22_packets` through `enable_r22_v9_packets`, `disable_pip_r26_packets`,
`hr_ch_switching`, `ir_hw_switching`, `enable_sig11_during_sleep`, `enable_sig12`,
`enable_frizzle_burst_mode` and `ir_1x_enable`, followed each time by
`SENSORS: No active sources`.

### Session 5 (2026-09-12): a clean session

Of five sessions since session 4, two long unattended ones showed the usual mix of
`0x2F`–`0x32` traffic. The most recent, ~6.5 minutes, had 397 frames that were all
`0x28` or `0x24`. That points to the burst and log traffic coming from the official
app's own activity rather than the band on every connection; one clean session, not
a controlled test. Heart rate held at 1 Hz, 65–95 bpm. Across all sessions, 1,327
responses and none to HELLO or battery, which led to the one-byte-body test above.
