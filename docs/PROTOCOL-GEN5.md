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
