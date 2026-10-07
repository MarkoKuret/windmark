# Networking

How Windmark races are played online: an authoritative headless server runs the core; clients send inputs,
predict their own boat and show everyone else slightly in the past; the server alone decides collisions, rules,
penalties and results. This file specifies the protocol, the timing, the message formats and budgets, joining and
leaving, anti-cheat, the transport and the lobby/matchmaking around it.

Targets: up to 40 boats per race (any mix of humans and AI), playable at 150 ms round trip and tolerable at 300 ms,
typical downstream under 10 kB/s per client, upstream under 2 kB/s, Steam Deck and low-end PCs as clients.

Conventions: `conventions.md` (50 ms tick `DT`, ENU frame, compass angles, `twa` sign, binary32, checksums §9)
and `race.md` §0. All integers little-endian. Bit-packed fields are
written LSB-first into a byte stream.

## 1. Architecture

```
            ┌────────────────── game server process (headless) ──────────────────┐
 client ──► │  transport ─► input buffers ─► core tick: inputs, weather, physics,  │ ──► snapshots, events
 client ──► │                                collisions, race, rules, AI          │ ──► (per client)
 client ──► │  one core World per race; several races per process                  │
            └──────────────────────────────────────────────────────────────────────┘
                     ▲ register / allocate                     ▲ connect tokens
                 matchmaker / lobby service (HTTPS)  ◄───── players
```

- **Dedicated authoritative server**: runs exactly the same core library as the client (boats, wind, sea,
  collisions, race, rules, AI) at the fixed tick. It owns the only true state.
- **Clients**: send inputs; run the core locally for their own boat's **prediction** and for everything that
  can be computed from shared data (weather, sea, course); render other boats from server snapshots with
  **interpolation**.
- **Listen server** (private LAN games, offline split-screen in future): the host runs the server in-process on a
  thread with the same protocol over loopback. There is no peer-to-peer mode.
- AI boats exist only on the server (`ai.md`); to clients they are ordinary remote boats.

## 2. Determinism requirements

Prediction is exact, and replays re-simulate, only if the core gives bit-identical results on every platform:

- The arithmetic rules of `conventions.md` §5 (binary32, no contraction, no x87, denormals kept, fixed order) and
  the core's own math functions of §6 (`wm_sincos`, `wm_atan2`, `wm_exp`, …) instead of the platform libm, on the
  server and on every client build (x86-64, ARM64, and WebAssembly if a browser client is built).
- No iteration over unordered containers, no dependence on addresses, threads or wall time in the tick.
- Boat classes and venues are identified by the hashes of their performance and venue files (`data_format.md`
  §4.1, §7); a client with a different file does not join.
- The core version is identified by a **core hash** (git tree hash of `core/` plus the boat and venue data used).
  Client and server must match it exactly (handshake, §12.3).

Online correctness never depends on determinism (the server is authoritative); only the smoothness of prediction and
the validity of replays do. Divergence is detected (§10.2) and corrected like any misprediction.

## 3. Time

### 3.1 Ticks

- The server advances each race by one tick every DT of its monotonic clock. Tick numbers are `u32` from race
  creation. If the server falls behind by more than 5 ticks it runs catch-up ticks without sending snapshots in
  between, and logs it.
- Everything in the protocol is expressed in ticks: inputs, snapshots, events, the start signal (`n_gun`),
  penalties, results. Wall-clock time appears only in clock synchronisation.

### 3.2 Clock synchronisation

Every input packet carries the client's send time `t_c` (ms, u32, client monotonic clock). Each snapshot echoes the
latest `t_c` it received from that client with the server's hold time `h` (ms between receiving that packet and
sending this snapshot) and the server tick `T` and phase `φ` (ms into tick T at send time).

```
RTT sample  = now_c − t_c_echo − h
filter      = keep the last 16 samples (≤ 20 s old); RTT_est = min of them (latency floor);
              jitter_est = p90(samples) − RTT_est
server_now  ≈ T + (φ + RTT_est/2 + (now_c − recv_c)) / DT        (in ticks, fractional)
```

The estimate of `server_now` is itself smoothed: the client keeps a local tick clock and slews it towards the
estimate by at most 2 % of real time (never steps backwards; steps forwards only when the error exceeds 250 ms).

### 3.3 Client lead and time dilation

The client simulates its own boat **ahead** of the server so its input for tick k reaches the server before the
server simulates k:

```
lead_ticks = ceil((RTT_est/2 + jitter_est + margin) / DT),   margin = 1 tick
client predicted tick  k_pred = floor(server_now) + lead_ticks
```

The server measures, per client, the **arrival margin**: for each input it uses, how many ticks before its use it
arrived (0 = just in time, negative = too late). Each snapshot carries the smoothed margin (int8, ticks ×4). The
client then runs its simulation clock at 97 %–103 % of real time to keep the margin at +1 tick: slower when the
margin is above 2, faster when below 0.5. This absorbs clock drift and route changes without visible jumps.

### 3.4 Start on the common clock

The start signal is the tick `n_gun` in the race parameters (§7). Every signal of the sequence (`race.md` §3.2) is
derived from it by every client, and the countdown shown is `(n_gun − server_now)·DT` (interpolated view time for
remote events, predicted time for the own boat's start panel). No timer is ever sent.

## 4. Inputs

### 4.1 Input frame

One per boat per tick, what a player (or the AI, `ai.md` §11) sets:

| Field | Encoding | Meaning |
| --- | --- | --- |
| `h_cmd` | int16, −32767 … 32767 ↔ −1 … +1 | commanded helm, + turns the bow to starboard (`boat.md` §2) |
| `sheet_cmd` | u16, 0 … 65535 ↔ 0 (sheeted hard in) … 1 (fully eased) | the one manual sheet control (`sails.md` §5.2); ignored while `auto_trim` |
| `sail_req` | u8: 0 = none, 1 … 15 = `hoist(front sail index + 1)`, 255 = `drop_front()` | sail request event (`sails.md` §4.2); applied once, on the tick it is stamped |
| `flags` | u8 bits: 0 `let_fly`, 1 `auto_trim`, 2 hail (rule 20), 3 hail reply, 4 protest, 5–7 reserved | |

Encoded frame: 6 bytes. Consecutive frames are delta-coded (below) because most ticks repeat the previous values.

### 4.2 Input packet (client → server, every client tick)

```
header (transport §11)
u32  t_c                    client send time (ms)
u32  ack_snapshot           newest snapshot tick received
u32  ack_bits               bit i = snapshot (ack_snapshot − 1 − i) received (baseline selection, §5.4)
u32  first_tick             tick of the first frame below
u8   n                      frames in this packet (1 … 8): the frames for first_tick … first_tick + n − 1
frames: frame 0 in full; each later frame: u8 mask of changed fields + changed fields
```

A packet carries the inputs of the newest `n` ticks that the server has not confirmed (the server confirms with
`last_input_tick` in every snapshot). Normally n = 3–4, so a lost packet costs nothing. Typical packet: 30–40 bytes
of payload.

### 4.3 Server input buffer

Per client, a ring buffer indexed by tick (64 entries). When the server simulates tick k:

- the stored frame for k is applied;
- if none arrived, the server **holds** the last applied frame, marks tick k as held for that client, and
  reports it (`held_ticks` bits in the snapshot); a frame for k that arrives later is dropped;
- frames for ticks already simulated are ignored; frames more than 20 ticks (1 s) ahead are rejected (§11).

### 4.4 Discrete actions

Retire, chat, ready and lobby actions go on the reliable channel as messages (§8.3), not in the input frame.

## 5. Snapshots (server → client)

### 5.1 Schedule and distance bands

The server sends each client one packet per tick (20 Hz). Its content is chosen per client by **interest bands**,
measured from the client's own boat (spectators: from the camera focus they report):

| Band | Condition | Target rate |
| --- | --- | --- |
| A | the client's own boat | every tick |
| B | within 150 m, or in any rules pair record with the own boat (`rules.md` §11.1), or within 10 own hull lengths | every tick |
| C | 150–500 m | 10 Hz |
| D | 500–1500 m | 5 Hz |
| E | beyond 1500 m | 2 Hz |

The first three boats of the live ranking are at least band D. A **priority accumulator** turns bands into a packet:
each entity's priority grows by `w_band · DT` every tick (`w_A = w_B = 20`, `w_C = 10`, `w_D = 5`, `w_E = 2` per
second); each tick the entities are written in descending priority until the tick's byte budget (§5.6) is used;
written entities reset to 0. With enough budget this gives exactly the target rates; with too little the rates of
far boats fall first.

### 5.2 Snapshot packet

```
header (transport §11)
u32  tick                   server tick T of this state (after the full tick, race.md §1)
u32  last_input_tick        newest input tick of this client the server has applied
u32  held_ticks             bit i = the server held (did not have) this client's input at tick (last_input_tick − i)
u32  t_c_echo; u16 h_ms; u8 phase_ms_div4; i8 arrival_margin_q2        (§3.2, §3.3)
u32  baseline_tick          the snapshot this one is delta-coded against (0 = none, full)
own block                   §5.5
u8   n_entities; entity blocks, §5.3
u8   n_pairs; pair blocks, §8.2 (rules relations of the own boat, at 10 Hz: every second tick, else 0)
u32  hashes flag + hashes   §10 (own-state hash every tick; weather hash every 5 s)
```

### 5.3 Entity state (remote boats)

Quantised fields of one boat, in the order written:

| Field | Bits | Encoding |
| --- | --- | --- |
| `boat_id` | 6 | index in the race's entry list (≤ 64 boats) |
| `x`, `y` | 24 + 24 | signed fixed point, 1/128 m (7.8 mm), relative to the course origin (±65 km) |
| `heading` | 16 | ψ / 2π · 65536 |
| `vx`, `vy` | 16 + 16 | velocity over ground, signed, 1/1000 m/s (±32.7 m/s) |
| `turn_rate` | 12 | heading rate (`boat.md` §5.9), signed, 0.05 °/s (±102 °/s) |
| `heel` | 10 | φ, signed (+ = starboard down), 0.2° (±102°) |
| `helm` | 8 | `h`, signed, 1/127 |
| `front` | 4 | front sail index (15 = none) |
| `change` | 3 + 4 + 6 | the running sail-change step: sail index (7 = idle), phase (`sails.md` §3.1), progress 1/63 |
| `beta_main`, `beta_front` | 10 + 10 | sail angles β, signed, 2π/1024 (0.35°) |
| `pole` | 8 | spinnaker pole/tack angle, signed, 1.4° |
| `flags` | 8 | ghost, penalty turn in progress, OCS/returning, finished, let-fly, in irons, reserved ×2 |
| `input` | 48 | the boat's last applied input frame, band A/B only (for close-quarters extrapolation, §6.4) |

Full block: 205 bits = 26 bytes (+6 bytes of input in band B). Pitch, heave, sail shape and the wake are not sent:
for remote boats the client runs the boat's heave and pitch springs (`boat.md` §6.1) on the interpolated pose and
the local sea for the visuals only, and derives the sail shapes from the sent sail angles (`sails.md` §7).

### 5.4 Delta compression and baselines

- The **baseline** is the newest snapshot the client has acknowledged (`ack_snapshot`/`ack_bits` of §4.2) that the
  server still keeps (it keeps the last 32 per client). The server writes `baseline_tick`; without one, blocks are
  full.
- Per entity present in the baseline: a u16 field mask (which fields changed), then the changed fields. Positions are
  coded as the **residual** against the baseline position extrapolated with the baseline velocity over the tick
  difference, as zig-zag varints of the quantised units; for a boat sailing straight the residual is a few units,
  1 byte each. Heading likewise against `heading + turn_rate·DT·ticks`.
- Entities not in the baseline, or whose last copy is older than 1 s, are sent in full.
- Typical delta block for a sailing boat: 9–12 bytes.

### 5.5 Own-boat block

Every snapshot carries for the client's own boat:

- the same quantised state as §5.3 (for the HUD of spectators and the render fallback), always full or delta-coded;
- a **64-bit state hash** of the own boat at tick T: FNV-1a 64 (`conventions.md` §9) over the tick index and the
  boat's snapshot bytes (`boat.md` §3 then `sails.md` §3, in the specs' order), followed by the boat's race and rules
  state that prediction touches (next step, winding angles, turn-tracker values);
- every second tick, and on every tick with a held input for this client, the **full own state**: exactly those
  snapshot bytes (about 60 bytes of boat state plus 10 bytes per sail and the sail queue, ≤ 200 bytes for the
  largest inventories). This is what the client reconciles to (§6.2).

### 5.6 Byte budgets

Per client downstream budget: default **16 kB/s** (0.8 kB per tick), minimum profile 6 kB/s, maximum 32 kB/s,
chosen by the client's measured capacity (loss and RTT growth on increase, §11.4). The per-tick budget is spent in
this order: header and own block, events on the reliable channel (§8), pair blocks, then entities by priority.
A packet never exceeds **1200 bytes** of payload; nothing is fragmented at the IP level.

Worked example, 40 boats, client in the middle of the fleet, 6 boats in band B, 10 in C, 15 in D, 8 in E:

| Item | bytes/s |
| --- | --- |
| headers + clock + acks (≈ 36 B × 20) | 720 |
| own block (delta ≈ 12 B + hash 8 B) × 20, full state ≈ 150 B × 10 | 1 900 |
| band B: 6 × 20 Hz × (12 B + 6 B input) | 2 160 |
| band C: 10 × 10 Hz × 11 B | 1 100 |
| band D: 15 × 5 Hz × 12 B | 900 |
| band E: 8 × 2 Hz × 14 B | 224 |
| pair blocks: ≈ 4 pairs × 6 B × 10 Hz | 240 |
| events, race state (§8) | ≈ 200 |
| UDP/IP (28 B) + AEAD tag (16 B) × 20 | 880 |
| **total** | **≈ 8.3 kB/s (66 kbit/s)** |

Upstream: 20 packets/s × (28 IP/UDP + 12 transport header + 16 tag + ≈ 34 payload) ≈ 1.8 kB/s.

## 6. Client simulation

### 6.1 Prediction

Each client tick `k_pred` (§3.3): read the local controls into an input frame, store it in the input history,
send it (§4.2), and step the **own boat** with the core for that tick using:

- the weather and sea at tick `k_pred` (deterministic from the shared parameters, §7.2);
- the wind shadow and collisions from the remote boats as the client shows them (§6.3, §6.4) at that tick;
- the course and race logic for the own boat (line crossings, rounding) as a *prediction* for the HUD; official
  results come from the server (§8).

The predicted state of each tick is kept (ring buffer, 64 ticks) with its hash.

### 6.2 Reconciliation

When a full own state for tick T arrives (§5.5), and also when only a hash arrives:

```
if hash(T) == predicted_hash(T):           # prediction was exact
    drop predicted history ≤ T
else:
    own_state ← server state at T          (full state; with only a hash, wait for the next full state, ≤ 2 ticks)
    for k in T+1 … k_pred:                 re-simulate with the stored inputs of k and the remote boats as shown for k
        step own boat
    visual error  e = old_render_pose − new_render_pose (position, heading)
    if |e.pos| > 3 m or |e.heading| > 15°: snap (e = 0)
render pose = simulated pose + e,  e decays with τ = 150 ms (per frame: e *= exp(−dt/τ))
```

Mispredictions come from held inputs (§4.3), contact with remote boats, wind shadow from remote boats shown at a
slightly different place, and any platform divergence (§10.2). With a stable connection and no nearby boats the own
boat is never corrected.

### 6.3 Remote boats: interpolation

- **View time** for remote boats `t_view = server_now − D_interp`, with `D_interp` adaptive between **100 and
  150 ms**: `clamp(2·DT + jitter_est, 100 ms, 150 ms)`.
- Each remote boat keeps its received samples (tick, quantised state). The pose at `t_view` is interpolated between
  the two samples around it: position by cubic Hermite using the sampled velocities, heading by Hermite with the
  sampled turn rates, heel/helm/sail angles linearly (sail angles with `angle_lerp`).
- Lower-rate bands (C–E) and lost packets: if `t_view` is later than the newest sample, the boat is **extrapolated**
  with constant velocity and turn rate for up to 500 ms, then held. When a new sample arrives, the extrapolated pose
  blends to the interpolated one over 200 ms.
- Pitch, heave, wake and sail shape are computed locally from the pose, the sea and the wind.

### 6.4 Close-quarters mode

In close quarters the own boat is shown at the predicted present while others are shown ~(RTT/2 + lead + 120 ms) in
the past, which would make near-contacts look wrong. So remote boats within `6·L` of the own boat (and in band B)
are shown at the **own predicted tick** instead: the client takes the boat's newest server state and steps it with
the core physics forward to `k_pred` using the boat's last applied input (sent in band B, §5.3), held constant.
Entering and leaving this mode blends the pose over 300 ms. These predicted remote boats are also what the own boat's
predicted collisions and wind shadow use. They are corrected every snapshot like the own boat (without history:
the next snapshot simply restarts the forward step).

### 6.5 What the client never decides

The client may show a predicted contact bounce and predicted line crossings immediately for feel, but penalties,
right-of-way verdicts, roundings, finishes, ranks and results are shown only as the server reports them (§8).

## 7. Race parameters and shared world

### 7.1 Race parameters (reliable, at join)

```
race_id (u64), protocol version, core hash (§2)
course: the resolved course in canonical JSON (courses.md §9), deflate-compressed, and its SHA-256
race_seed (u64, conventions.md §7), t_env0_ms (race.md §0)
weather: the wind settings of wind.md §1 (base, shifts, oscillation, puffs, current, venue field reference)
sea: the settings of sea.md §2, including sea_hs and sea_tp as computed by the server (clients never derive them)
classes: per class id, class_version and the SHA-256 of its performance file; venue id, version and file SHA-256
settings: race.md §2 record (sequence, flags, rules level, umpire mode, penalties, limits, assists allowed)
n_created, n_gun, DT
entries: per boat: id, class, name, colours, human/AI, AI level, team; spawn pose
your_boat_id (or spectator)
```

The client loads the course, the classes and the venue, builds its local world, and replies `Ready`. It then starts
predicting at `k_pred` (§3.3).

### 7.2 Shared-seed weather

The wind is a pure function of `(race_seed, t_env_ms, position)` (`wind.md`) and the sea a pure function of its
settings, the seed and time (`sea.md`), so neither is ever streamed: the race parameters carry the settings and the
seed once, and every client computes the wind at its own boat for prediction and the puffs and waves for the
visuals. A late joiner computes the present weather directly from the tick. Only the wind shadow depends on boat
positions: the server's shadow uses the true positions; the client's uses the remote boats as shown (§6.3, §6.4);
the difference is a small misprediction corrected by reconciliation.

## 8. Race and rules state

### 8.1 Events (reliable ordered channel)

Every race event (`race.md` §11) and rules event (`rules.md` §11.3) is sent to every client with its tick, in tick
order, compactly coded (event type u8, tick u32 delta-coded, boat ids u8, rule code u8 from a fixed table, values).
Clients apply them to their race view; the HUD shows them at the view time of their tick (events about the own boat
at once).

### 8.2 Pair relations of the own boat (unreliable, 10 Hz)

For each rules pair record involving the client's boat (`rules.md` §11.1): other boat id (u8), relation (3 bits),
keep-clear direction and rule (5 bits), keep-clear state (2 bits), room direction, rule and state (6 bits),
limitation bits (6 bits), rule-17 holder (1 bit), gap (u8, 0.1 m up to 25.5 m, 255 = more), ttc (u8, 0.1 s, 255 = none).
6 bytes per pair. These drive the radar colours and the rules messages (`hud.md` §8, §11). Spectators receive the
pairs of the boat they follow.

### 8.3 Race state summary (reliable, 1 Hz, delta)

Per boat: race status (pre-start / OCS / racing / finished / ghost code), next step, rank, pending penalties count,
turn progress (u8), deadline (u8 s), DSQ/RET flags, finish time when finished. Used to rebuild the view after a lost
event and at join.

### 8.4 Chat and lobby messages

Reliable ordered; chat limited to 200 characters and 1 message per 2 s per player; quick messages ("Starboard!",
"Room!", "Sorry") are fixed ids.

## 9. Joining, leaving, reconnecting

- **Join before the warning signal**: the player gets a boat on a free spawn slot (`race.md` §3.5). If the race is
  full and has AI boats, the AI boat with the highest entry index is removed (it becomes a ghost and disappears)
  and its slot freed.
- **Join between the warning and the preparatory signal**: allowed if there is room; the boat spawns at the back of
  the spawn grid. If full, the player spectates.
- **Join after the preparatory signal**: spectator until the next race of the lobby.
- **Leave** (quit or kick): before the warning signal the entry is removed (the lobby may fill with an AI); after the
  warning signal the boat becomes a ghost and scores DNS (before the start) or DNF (after, `race.md` §9).
- **Connection lost**: no packet for 2 s → the server marks the player "connection lost"; its inputs are held.
  After 3 s an AI takes over the boat (`ai.md` §14). The player may **reconnect** with the session token within 60 s:
  the server sends the race parameters and a full state (the world snapshot of `conventions.md` §9.1: all boats,
  collisions, race and rules state), and the player takes control again at a tick of the server's choice ≥ 3 ticks
  ahead, announced to the client. After 60 s the boat is retired (ghost, scored DNF, or RET if the player had asked
  to retire).
- **Server-side boat removal** never renumbers entries: boat ids are stable for the race.

## 10. One verdict, and consistency checks

### 10.1 Single authority

Collisions, contact responses, the rules engine (right of way, room, penalties, penalty turns, DSQ), race progress
(starts, OCS, roundings, finishes), time limits and scoring run on the server only. There is one verdict per
incident, made from the true positions of both boats at the same tick. Clients display it. Protests (protest umpire
mode) are sent as a reliable message and judged by the server.

### 10.2 Hash checks

- **Own-state hash** (§5.5): a mismatch with an exact input history (no held ticks, no remote boats within
  `10·L` or in the shadow range) is a **divergence**. The client counts them; more than 5 in 30 s triggers a
  telemetry report with the two full states and the platform, and a message in the debug overlay. Gameplay continues
  (reconciliation fixes it).
- **Weather hash** every 5 s: the server hashes the clean wind `wind_clean` (the raw binary32 bits of speed and
  direction) and the sea height at 16 fixed probe points of the course at tick T; the client compares with its own. A
  mismatch can only be a platform or build divergence (the weather is a pure function): the client reports it with
  both values; play goes on, since the server's physics is authoritative and reconciliation corrects the own boat.
- **World hash** every 5 s (the tick checksum of `conventions.md` §9 over the world snapshot body: all boats,
  collisions, race and rules state): written to the server log and the replay file, used by replay verification
  and tests, not sent to clients.

## 11. Transport

### 11.1 Packets and channels

UDP. Every packet: `u32 protocol_id`, `u64 connection_id` (from the connect token), `u16 seq`, `u16 ack`,
`u32 ack_bits` (per-packet acknowledgements of the peer's last 33 packets), then one or more messages
`{u8 channel, u16 length, payload}`, then the AEAD tag.

| Channel | Delivery | Carries |
| --- | --- | --- |
| 0 | unreliable, sequenced (older than the newest received are dropped) | inputs, snapshots, pair blocks, pings |
| 1 | reliable, ordered | race parameters, events, race state summaries, chat, lobby, protests |
| 2 | reliable, unordered, fragmented | large blobs: course, full state at reconnect, replays |

Reliability for channels 1 and 2: messages are resent in the next packet after `max(1.25·RTT_est, 50 ms)` without an
ack; channel 2 blobs are cut into 1 kB fragments with a send window of 32. Packets never exceed 1200 bytes of UDP
payload.

### 11.2 Security

- **Connect tokens** from the matchmaker (§12): server address, client id, expiry (30 s), and per-connection keys,
  sealed with a key shared by the matchmaker and the game servers. The client presents the token in its connect
  request; the server answers with a challenge that the client must echo (prevents spoofed source addresses and
  amplification).
- All packets after the handshake are encrypted and authenticated (XChaCha20-Poly1305 or AES-GCM) with the
  connection keys and the packet sequence as nonce; replayed or forged packets are dropped.

### 11.3 Libraries

Any of these permissive options fits the design; the choice is made at implementation time and recorded in
`docs/THIRD_PARTY.md`: the netcode and reliable libraries by Glenn Fiedler (BSD-3-Clause), Valve's
GameNetworkingSockets (BSD-3-Clause), or ENet (MIT) with our own encryption layer. The protocol above (messages,
channels, timing) is ours either way.

### 11.4 Congestion

The server measures per client the loss rate and RTT trend. On loss above 5 % or RTT rising 50 % above its floor, the
downstream budget drops 25 % (never below 6 kB/s); after 10 s of clean delivery it rises 10 %. The priority
accumulator (§5.1) then lowers the far bands first.

### 11.5 Browser clients (if one is ever built)

- **WebTransport** (HTTP/3): channel 0 over datagrams, channel 1 over one bidirectional stream, channel 2 over
  unidirectional streams. A gateway next to each game server terminates WebTransport and forwards to the game
  server's UDP protocol (same messages, TLS instead of our AEAD on that hop).
- Fallback **WebRTC data channels** (for browsers without WebTransport): one unordered channel with
  `maxRetransmits = 0` for channel 0, one reliable ordered channel for channels 1 and 2.
- The core compiled to WebAssembly for prediction, with the same determinism rules (§2; WebAssembly `f32` is
  IEEE-exact and has no implicit FMA).

## 12. Lobby, matchmaking, ratings

### 12.1 Services

- **Matchmaker / lobby service** (HTTPS JSON API): player sessions, queues, private lobbies, ratings, server
  allocation. Game servers register with region, capacity and core hash, and send heartbeats.
- Game servers run many races per process (a 40-boat race costs on the order of 1–2 ms per tick of CPU).

### 12.2 Modes and queues

| Mode | Boats | Format |
| --- | --- | --- |
| Quick race | 1–16 humans, filled with AI to 10 boats | one race, 10–15 min, wind-relative course scaled to `target_duration_s` (`courses.md` §6.3) |
| Series | 4–20 humans, AI fill to 10 | 3 races, low-point series (`race.md` §9) |
| Match race | 2 humans (or 1 + AI) | first to 2 wins |
| Private lobby | host's choice (up to 40) | any settings, invite code, optional AI fill, protest umpire mode allowed |

Weather (`race.md` §2.1): quick races, series and match races (the scheduled and ranked rooms) use the Local or
Random weather mode only; Custom is for private lobbies and offline play. This is the rule for phase 4.

Region choice: the client pings the regions' probe endpoints at start and queues in the lowest-RTT region (≤ 120 ms);
otherwise the best available with a warning.

### 12.3 Handshake checks

The connect request carries the protocol version and the core hash; a mismatch is refused with "update required".

### 12.4 Filling with AI

A quick race waits up to 30 s for humans, widening the rating window every 10 s, then starts with AI boats up to the
target fleet size. The AI level is chosen from the humans' mean rating: bottom 30 % of the population Easy, next 40 %
Intermediate, next 20 % Expert, top 10 % Pro; mixed fleets draw each AI's level from the neighbourhood of that level
(±1 with 25 % probability each). AI boats never get a speed boost relative to their level (`ai.md` §13).

### 12.5 Ratings

A multiplayer rating per mode (OpenSkill-style Plackett–Luce model, permissive implementation or our own), updated
from the finishing order of the human boats only; DNF, DNS, OCS and disconnects count as last. AI boats do not enter
the rating update. Races with fewer than 2 humans do not change ratings. Abandoned races do not count.

### 12.6 Lobby flow

```
Queue ─► Lobby (players join, boats and colours) ─► Launch countdown 20 s ─► Race (race.md) ─► Results 20 s
      ─► next race of the series, or back to Queue
```

The race is created at the end of the launch countdown; the free-sailing period (`race.md` §3) gives late-loading
clients time to join before the warning signal.

## 13. Anti-cheat

The server's authority removes position, speed, teleport and result cheating: clients only send inputs. What remains
is checked on the server:

- **Input validation**: every field in range (§4.1), no NaN (integers only), `sail_req` must be a sail of the class
  and allowed now (`sails.md`), sheets and tiller changes are free (a human can move them instantly), sail requests
  at most 2 per second, hails at most 1 per 5 s, protests only during a protestable incident.
- **Tick window**: inputs for ticks already simulated are ignored; more than 20 ticks ahead are rejected; a client
  whose inputs arrive consistently far ahead (clock running fast, "speed hack") gains nothing because the server
  simulates at its own rate, and after 10 s of margin above +10 ticks it is told to resynchronise, after 60 s kicked.
- **Rates**: more than 2 input packets per tick on average over 5 s, or oversized packets, are dropped; persistent
  flooding closes the connection.
- **Information**: every client already sees every boat (racing is open information); the only private data are
  other players' inputs, which the server sends only for band B boats and only their last applied frame.
- **Automation**: inputs from scripts are not detectable in principle; ranked play relies on the server log. Every
  ranked race keeps its replay (§14) for 30 days for review of reports.
- **Accounts**: connect tokens bind a connection to an authenticated account; kicks and bans are by account.

## 14. Spectators and replays

- **Spectators** connect like players without a boat; their bands are measured from the camera focus they report (a
  reliable message when it changes). Broadcast spectators (tournaments) may get a higher budget.
- **Replays**: the server writes race parameters, every boat's applied input per tick (held ticks marked), all events,
  and the world hash every 5 s. A replay is re-simulated by the core; its hashes must match. A replay may also
  carry world snapshots (`conventions.md` §9.1) as seek points: loading one and re-simulating from it reproduces
  the same hashes as simulating from the start. Files carry the core hash and are only valid for that version.
  Typical size: ~2 bytes per boat per tick after delta coding and compression (40 boats × 15 min ≈ 1.4 MB).

## 15. Tests

- Loopback harness with a simulated network in-process: RTT 0–300 ms, jitter 0–50 ms, loss 0–10 %, reordering.
- With no loss and no nearby boats, the own boat is never corrected over a 10-minute race (exact prediction).
- With 5 % loss, the input redundancy keeps held server ticks below 0.1 %.
- The own boat's visual correction never exceeds 0.5 m per frame except snaps; snaps occur only after contacts.
- Bandwidth: a 40-boat race stays within the per-client budget in every band configuration; packets never exceed
  1200 bytes.
- Late join before the warning signal, join as spectator after the preparatory signal, disconnect and reconnect within
  60 s with AI takeover in between, reconnect after 60 s (retired).
- A deliberate bit flip in the client's weather produces a weather-hash mismatch and a resync within 5 s.
- A replay of a recorded race reproduces every 5 s world hash on all supported platforms.
