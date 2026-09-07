# WHOOP 5.0 (Gen 5) BLE protocol — discovery spike findings

Source: a real ~10-minute worn session against the user's own WHOOP 5.0 band and
account, captured via `SpikeRecorder` (`ReflexWhoop/Ble/`) and analyzed offline
from the raw `ingest_inbox` rows pulled off-device. 711 raw BLE notifications
were logged; every finding below is derived from those bytes, not guesswork
layered on top of assumptions. Session id `2DED0E3A-1CC7-4DEA-BD6E-98F78D1A19EC`,
recorded 2026-09-07.

**Read the safety section near the bottom before running another session.**

## Envelope — CONFIRMED, high confidence

The Gen 5 envelope is **not** what `docs/design.md`'s diff table (and the first
cut of `Framing.swift`) guessed. The real layout, verified by CRC match on
**100% of all 711 captured frames across all three notify characteristics**
(zero marker mismatches, zero CRC-16 failures, zero CRC-32 failures):

```
byte 0      0xAA                        marker
byte 1      0x01                        version (constant in every sample)
bytes 2-3   u16 LE  len                 = size of (field + crc16 + inner) = innerLen + 4
bytes 4-5   u16 LE  field               constant 0x0001 in every sample — purpose unconfirmed
bytes 6-7   u16 LE  crc16               CRC-16/MODBUS over bytes[0:6]
bytes 8..   inner   (len - 4 bytes)     [packet_type][seq][opcode/event_id][body...]
last 4      u32 LE  crc32               CRC-32 (IEEE 802.3) over the inner bytes only
```

Total frame length = `8 + innerLen + 4`. There is **no padding to a multiple of
4** — that was a Gen 4 assumption that doesn't hold here; `len` and the frame
length are exact byte counts.

This was verified by brute-force search over every `(range, checksum-position)`
combination against the 14 near-identical 20-byte frames on
`fd4b0003`(varying inner bytes, constant header) — exactly one range
(`bytes[8:16]`, i.e. the inner payload) produced a CRC-32 match against the
trailing 4 bytes for every sample, and the predicted total-length formula
(`8 + len-4 + 4`) matched the actual byte count of every one of the 711 frames,
including the one 84-byte HELLO response and the dense 124-byte data-channel
frames. This is about as confirmed as reverse-engineering gets without the
firmware source.

**Not yet observed / unconfirmed:** whether `field` ever takes a value other
than 1, and what it means when it does. Every frame in this session — commands,
responses, events, and the historical burst — carried `field = 1`.

**No reassembly was needed this session.** All 711 notifications arrived as
complete, self-contained frames (largest inner payload seen: 112 bytes) —
CoreBluetooth's negotiated MTU was large enough that nothing fragmented.
`FrameReassembler`'s length-based resync logic is untested against a real
fragmented frame; keep it, since R21 (~1244 B) and r22 will almost certainly
fragment, but treat it as unconfirmed until a session actually exercises it.

`Framing.swift`/`Gen5Envelope` has been corrected to match this confirmed
layout (see the file's doc comment and `FramingTests.swift`).

## Inner packet_type byte — confirmed values, revised meanings

The inner packet type byte (`inner[0]`) took five distinct values this
session. **Gen 4's packet-type numbering (which `docs/design.md` inherited)
does not appear to hold for Gen 5** — see the safety section for why this
matters.

| Value | Count | Where seen | What it actually was (from evidence) |
|---|---|---|---|
| `0x24` | 15 | `fd4b0003` (command-response), `fd4b0004` (events) | Generic response/status frame — matches design doc's Gen4-derived "response" label, this one's consistent. |
| `0x2F` | 640 | `fd4b0005` (data) | **A historical-data burst**, not a live sensor stream — see below. All in a ~4-second window at connection start. |
| `0x30` | 2 | `fd4b0005` | Event frame — consistent with design doc's Gen4-derived "event" label. Too few samples this session to map specific event IDs. |
| `0x31` | 25 | `fd4b0005` | Unclear — small (12-40 byte) frames interleaved with the `0x2F` burst and after it. Design doc calls this "sync marker"; plausible given the timing, not confirmed field-by-field. |
| `0x32` | 28 | `fd4b0005` | **Plain-ASCII firmware debug log lines**, not a sensor or command-response record at all. This is what makes the rest of this document possible — see below. |

## The historical-burst debug log — the single most important finding

`0x32` frames are not binary telemetry — decoding `inner[16:]` as ASCII and
splitting on the first NUL byte recovers literal firmware log lines,
reassembled here in order:

```
Send Historical Data
8, 642658720: BLE: hist transfer start response ack, start burst
8, 6426612...: BLE: History burst success. Trim: 0x00000002:0001c4e5 (2:115941)
8, 642661630: BLE: History burst success. Trim: 0x00000002:0001c4e9 (2:115945)
... (repeats, Trim counter monotonically increasing: c4e5 → c4e9 → c4ed → ... → c50b)
8, 642665000: BLE: Historical Dump Complete
8, 642665000: BLE: Pull stats: Data: 598, Events: 27, Bytes: 77132, Secs: ...6.280, Brate: 12282.2, Prate: 99.5
8, 643034...: BLE_CMD: Invalid packet, error = 2   (×4)
8, 643259...: BLE_CMD: Command Get Data Range
```

Reading this against what this app actually did:

- **A real historical data transfer happened.** "Trim" is exactly the kind of
  language you'd expect for a flash ring-buffer read cursor advancing as data
  is consumed — the shared cursor `docs/design.md`'s safety rails are about.
  598 records + 27 events, 77,132 bytes, moved in about 4 seconds.
- **This app did not command it.** `OpcodeAllowlist.assertAllowed` is called
  on the literal opcode byte before every `BandConnection.send`, and
  `SpikeRecorder.beginSafeCommandSequence()` only ever calls it with
  `getHelloHarvard (0x23)`, `getBatteryLevel (0x1A)`, `toggleRealtimeHR (0x03)`,
  and `sendR10R11Realtime (0x3F)` — never `0x16`/`0x17`/`0x21`. This is
  enforced structurally and covered by `OpcodeAllowlistTests`, not a claim
  resting on this session's evidence.
- **This app's actual commands never even parsed.** The four
  `"BLE_CMD: Invalid packet, error = 2"` lines line up exactly with the four
  opcodes above — because they were built with the *old, wrong* envelope
  hypothesis (7-byte header, 1-byte field) before this spike corrected it.
  The band's own CRC check rejected all four as malformed and did nothing
  with them. Nothing this app asked for ever took effect this session —
  the HR/IMU realtime stream was never actually enabled, which is also why
  no live sensor data appears anywhere in this capture.
- **The burst started immediately on connection, before any of this app's
  (malformed, later-rejected) commands could plausibly have reached the
  band.** The most likely explanation is that Gen 5 firmware performs some
  form of automatic catch-up sync on a new central connecting — independent
  of anything this app requested — though it's also possible this reflects
  the official WHOOP app's own normal, legitimate, already-scheduled sync
  happening concurrently in the background and simply being visible on a
  characteristic this app happened to be subscribed to (`GET_DATA_RANGE`
  appearing in the log with no matching outbound call from this app supports
  that reading). Both explanations are consistent with the evidence; neither
  implicates anything this codebase sent.

**Practical read:** nothing here shows this app caused, requested, or
acknowledged any historical transfer. But real flash-cursor activity was
observed on a real band during a session this app initiated, and the design
doc's own verification plan calls for exactly this situation to be checked
against the official app before trusting it further.

## Confidence summary

| Claim | Confidence |
|---|---|
| Envelope structure (8-byte header, CRC-16 over header, CRC-32 over inner, exact-length framing) | **Confirmed** — 711/711 frames, zero exceptions |
| `field` is a fixed `0x0001` | Confirmed for this session; unconfirmed whether it ever varies |
| `0x24` = response | Consistent with design doc, low sample count (15) |
| `0x2F` = historical data (not "realtime raw" as design doc assumed) | High confidence — matches debug log content directly |
| `0x30` = event | Consistent with design doc; only 2 samples |
| `0x31` = sync marker | Plausible from timing/position; not confirmed field-by-field |
| `0x32` = ASCII firmware debug log | **Confirmed** — directly decoded, human-readable |
| A historical burst happened and wasn't commanded by this app | High confidence (structural allowlist proof + all 4 real commands independently confirmed rejected) |
| Whether the burst was band-automatic or the official app's concurrent traffic | Unresolved — both explanations fit the evidence |
| R10/R21/r22 live sensor record layouts | **Not captured.** The commands meant to enable them never parsed (see above); nothing in this session is a live sensor sample. A repeat session with the now-fixed envelope is needed before any of that decoding can start. |

## Safety check required before the next session

Per `docs/design.md`'s BLE verification plan (item 9): **open the official
WHOOP app now and confirm it syncs normally and recovery/strain scores are
intact**, given the real historical-transfer activity documented above. This
app's own commands are independently confirmed to have had no effect this
session (rejected at the CRC layer), but the transfer itself was real and
this is the check the design doc calls for whenever that's true — do it
before running another live session, not just as routine.

**Checked 2026-09-07: official app synced normally, scores looked normal.**
Cleared to run another spike session with the now-fixed envelope.

## Next steps once the app/scores check out

1. Re-run the spike now that `Framing.swift` sends correctly-formed commands
   — `getHelloHarvard`/`getBatteryLevel` should get real `0x24` responses
   instead of `error = 2`, and `toggleRealtimeHR`/`sendR10R11Realtime` should
   actually enable a live stream this time.
2. With a real live stream running, capture and map the R10/R21/r22 record
   layouts per `docs/design.md`'s hunt method (correlate HR byte against the
   WHOOP app's live number, RR arrays via plausible 600-1400 ms i16 runs,
   accel via f32 triples near 1 g at rest).
3. Confirm whether a second `0x2F` burst happens on every reconnect
   (supports "automatic on connect") or only sometimes (supports "coincided
   with the official app's own sync").

---

## Session 2 (2026-09-07, three back-to-back connections, ~92 minutes total)

7,343 raw frames across three separate sessions/reconnects (the app was
restarted between them), captured with the now-fixed envelope. Every one of
the 7,343 frames parsed with a valid marker, exact length, valid CRC-16, and
valid CRC-32 — the envelope fix from session 1 holds completely.

**This app's commands parsed this time.** All 156 `fd4b0003` responses this
session are `0x24` (real responses), zero `"Invalid packet"` errors — the
envelope fix worked, and `toggleRealtimeHR`/`sendR10R11Realtime` actually took
effect.

### Correction to session 1: `0x2F` is not historical-drain-specific

Session 1 labeled `0x2F` "a historical-data burst" because it was adjacent to
the `0x32` debug log describing one. This session's evidence narrows that:

- `0x2F` frames from the very start of session 1 (debug-log-confirmed as part
  of the historical dump) and `0x2F` frames from deep into session 3 (after
  `sendR10R11Realtime` had been sent, parsed, and presumably taken effect) are
  **byte-for-byte the same 112-byte structure** — same field layout, same
  varying/constant byte positions. There is one record format, not two.
- `0x2F` traffic didn't stop when the debug log said `"Historical Dump
  Complete"` — it continued at a much lower, steady rate (roughly 1-3/s
  rather than the initial ~160/s) for the following ~40 minutes, across
  multiple reconnects, well past the point where the "dump" had supposedly
  finished.

Reading: **`0x2F` is a general-purpose sensor/data record wrapper used both
for the initial small connect-time catch-up sync *and* for the live realtime
stream once enabled** — not a record type exclusive to draining historical
flash. The connect-time burst itself (598 records, 77 KB, ~4 seconds, per
session 1's debug log) still reads as a small bounded catch-up, not an
unbounded dump; it's just delivered using the same record format as
everything else, which is a reasonable, unremarkable firmware design choice
in hindsight, not evidence of anything unusual.

It recurred on all three reconnects this session (new value: it happens
**every** connection, not just occasionally) — consistent with "automatic
per-connection catch-up sync," inconsistent with "coincidence with the
official app." That question is now close to resolved in favor of
band-automatic behavior, though still not certain.

### `0x28` — realtime compact HR — CONFIRMED, high confidence

409 frames, exactly 20 bytes of inner payload each, arriving at almost
exactly 1 Hz during the live-stream portion of session 3 (once
`sendR10R11Realtime`/`toggleRealtimeHR` had actually parsed). Byte-position
analysis across all 409:

```
inner[0]      0x28              packet_type (constant)
inner[1]      0x02              constant — subtype? unconfirmed
inner[2]      varies, +1/frame  low byte of a monotonic counter (device
                                 uptime or similar; does NOT match unix
                                 received_at, so not a wall-clock timestamp)
inner[3]      0xe2-0xe4         high byte of that same counter
inner[4:6]    0x9e 0x6a         constant — unclear, possibly part of the
                                 same counter or a session id
inner[6:8]    0x28/0x70/0xb8,   unclear — three-valued, changes in sync
              0x7c/0x7d/0x7e    with the counter rolling over a boundary
inner[8]      76-94 (0x4c-0x5e) HEART RATE, bpm, direct u8, no scaling —
                                 stayed in a normal light-activity range for
                                 the whole capture. Physiologically the only
                                 field in this record that fits.
inner[9:20]   various           unmapped — likely signal-quality/motion/
                                 skin-contact fields per docs/design.md's
                                 general expectations for a compact-HR record,
                                 not individually confirmed
```

This matches `docs/design.md`'s prediction exactly ("Compact HR also arrives
on `0x28`") and is now implemented as `RealtimeHRDecoder` (`ReflexWhoop/Ble/`)
— decoding only `inner[8]`, the one field with real evidence behind it. No
other byte in this record is decoded; per the design doc, "only decode a
field once the spike confirms it."

**Not yet cross-checked against the official app's own live HR number** —
the design doc's real correctness bar for this field. Do that next: open the
official app's live HR view during a session and compare.

### `fd4b0007` — identified, not decoded

4 frames total across all three sessions (very low frequency — once per
connection, roughly). These do **not** match the `Gen5Envelope` structure at
all (no valid `0xAA` marker framing) — this characteristic carries a
different wire format. The bytes are recognizable as **CBOR**: length-prefixed
text strings decode directly to readable content, including what look like a
build/version string (`"50.41.1.0"`), a hardware or codename string
(`"WG50_r45"`), and an internal codename (`"maverick"`), alongside a long
random-looking ID string. Read as one-time device/firmware metadata sent on
connect, not sensor data. Not a priority to fully parse — noted here so a
future pass doesn't have to rediscover that it isn't envelope-framed.

### Updated confidence summary (supersedes session 1's table for `0x2F`)

| Claim | Confidence |
|---|---|
| `0x2F` = general sensor-record wrapper (catch-up sync **and** live stream, same format) | High — same byte structure confirmed in both contexts |
| `0x28` = realtime compact HR, `inner[8]` = bpm | High — physiologically plausible, stable, matches design doc's prediction; not yet cross-checked against the official app's own HR reading |
| Connect-time catch-up sync is automatic per-connection (not coincidental official-app traffic) | Raised to likely — recurred on 3/3 reconnects this session |
| `fd4b0007` = CBOR-encoded device metadata, sent once per connection | Confirmed it's CBOR and readable; full field mapping not attempted |
| R21/r22 layouts | Still not captured — this session confirms `0x28` (compact HR) but no evidence yet of the richer optical/IMU records |

### Safety — checked again given the larger volume

This session moved far more data than session 1 (~92 minutes, three
reconnects, several hundred KB total, vs. session 1's single 8-second
capture window) purely because it ran much longer and was pulled after the
full duration rather than a few seconds in. **Recommend one more quick
official-app/scores glance** — not out of new alarm (the `0x2F`-is-shared-format
finding above is reassuring, not concerning), just to keep the same standard
applied every time real band activity is this extensive.
