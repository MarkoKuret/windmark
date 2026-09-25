# Racing rules engine

The automatic umpire: which boat must keep clear of which, who is entitled to room at marks and obstructions, when
a boat has broken a rule, who is penalised, how penalties are taken, and when a boat is disqualified. It runs in the
core on the authoritative side (server online, local process offline), once per tick in step 1 of the tick order
(`conventions.md` §4.1, `race.md` §1), right after race progress, on the state at `t_n` and the contact events of
the previous tick's collision step.

The engine follows the Racing Rules of Sailing (RRS) of World Sailing, 2021–2024 edition, Part 2 (when boats meet),
Part 3 rules 28–31 (with the starting parts in `race.md`) and Part 4 rule 44 (penalties), and Appendix C for match
races. This file explains each rule in our own words, cites its number, and then says exactly how Windmark decides
it from boat positions and motion. If a later RRS edition renumbers a rule, update the numbers here and in the event
codes (§11).

Conventions: `conventions.md` (frames, `twa` positive = wind from starboard, the tick, binary32 and `wm_*`
functions) and the race helpers of `race.md` §0 (`rules_tack`, sides, the rules hull = the collision outline,
the reference point `c` = the boat's `pos`). `L` is a boat's hull length,
`B` her beam; `L_max` the longest hull of the pair being judged.

## 1. What the rules talk about (definitions, in our words)

| Term | Meaning (RRS Definitions) | How Windmark measures it |
| --- | --- | --- |
| Tack, port / starboard | A boat is on the tack of her windward side. | `race.md` §0 `rules_tack`. |
| Tacking | From the moment a boat passes head to wind until she is on a close-hauled course. | §3.4. |
| Windward / leeward | Of two boats on the same tack, the leeward one is on the side of the other that is away from the wind; the other is windward. | §3.3. |
| Clear astern / clear ahead / overlap | A boat is clear astern when her hull is behind a line abeam from the aftermost point of the other's hull; the other is clear ahead. They are overlapped when neither is clear astern, or when a boat between them overlaps both. These terms apply between boats on the same tack, and on opposite tacks only when rule 18 applies between them or both are sailing more than 90° from the true wind. | §3.2. |
| Keep clear | A boat keeps clear of a right-of-way boat if the right-of-way boat can sail her course with no need to take avoiding action, and, when they are overlapped, if the right-of-way boat could also change course in both directions without immediately making contact. | §3.5. |
| Room | The space a boat needs, in the conditions, to manoeuvre promptly in a seamanlike way while complying with her obligations. | §3.6. |
| Mark-room | Room for a boat to sail to the mark and then her proper course while at the mark (and room to tack when she is overlapped inside and to windward and her proper course is to tack). | §7.4. |
| Proper course | The course a boat would sail to finish as soon as possible in the absence of the other boat. | §3.7. |
| Zone | The area around a mark within three hull lengths of the boat nearer to it. A boat is in the zone when any part of her hull is in it. | §7.1. |
| Obstruction | An object a boat could not pass without changing course substantially, when sailing directly towards it and one hull length from it: land, shallows, exclusion zones, committee boat when it is not a mark she is using, anchored objects. | §7.8. |
| Fetching | Sailing a course that will take her to the windward side of a mark and leave it on the required side without changing tack. | §7.6. |
| Racing | From the preparatory signal until she has finished and cleared the finish, retired or been disqualified. | `race.md` §3, §6. |

## 2. Engine structure

### 2.1 When rules apply

- Rules are active for a boat while she is **racing**: from the preparatory signal (`race.md` §3.2) until she
  becomes a ghost (`race.md` §6.3: `collides` and `casts` cleared). Between the warning and preparatory signals only
  collisions exist.
- `rules_level` (`race.md` §2): `none` = no rules, contacts only bounce; `basic` = rules 10–16, 22, 31 and
  penalties; `full` = everything in this file.
- Pairs: every unordered pair of racing boats whose hull gap (§3.1) is below `R_pair = 10·L_max` is judged each tick.
  Pairs farther apart have no relation; their per-pair state (§2.3) is dropped when the gap exceeds `12·L_max`.

### 2.2 Per tick pipeline

```
1. per boat:   geometry (hull, bow, stern, reference point, velocity over ground, turn rate), tack, tacking (§3.4),
               zone membership per mark (§7.1), penalty-turn progress (§9.3), boundary (courses.md §5.1)
2. per pair:   relation (clear astern / ahead / overlapped, §3.2), windward/leeward (§3.3), hull gap
3. per pair:   right-of-way obligation (§4): who keeps clear, under which rule
4. per pair:   rule 18 / 19 status and room entitlements (§7), rule 15 onset (§5.2), rule 17 status (§5.4)
5. per pair:   tests: keep-clear state (§3.5), room state (§7.4), escape tests where needed (§3.6)
6. per pair:   breaches this tick (§5, §7) and exoneration (§6.1) → incidents (§9.1)
7. contacts:   the previous tick's contact events (collisions.md §5) → incidents, mark touches (§8)
8. per boat:   penalties issued (§9.2), penalty turns served (§9.3), deadlines (§9.4), disqualification (§9.5)
9. publish:    per-boat and per-pair records (§11) for the AI, HUD and network
```

Pairs are processed in ascending `(i, j)` order with `i < j`; every quantity is computed from the state after the
physics of this tick, so the order does not change results.

### 2.3 State kept between ticks

Per boat: tack label and tacking flag with its start tick; last tick the tack changed; heading history for the turn
tracker; penalty list; zone entry ticks per mark; the start tick of the current course change (§5.3).
Per pair: relation this tick and last tick, tick of the last relation change; obligation `(giver, holder, rule)` and
its onset tick and onset cause (§5.2); rule-18 status per mark (§7.3); rule-17 flag (§5.4); keep-clear state machine
(§3.5); open incident (§9.1).

## 3. Geometry and tests

### 3.1 Hull gap and prediction

- **Hull gap** `g(A, B)`: the minimum distance between the two rules hull polygons (0 when they intersect). Convex
  polygons: separating-axis test for intersection, else the minimum over vertex–edge distances.
- **Motion model for prediction** (constant turn rate and velocity): each boat keeps her speed through the water
  `v`, her turn rate `r` (the boat's `turn_rate` output, `boat.md` §5.9, heading rate positive clockwise) and the
  current at her position; the boat model has no leeway (`boat.md` §6.4). Over a horizon the hull polygon is moved
  in sub-steps of 0.1 s: `ψ += r·0.1`, `c += (v·dir(ψ) + current)·0.1`, the polygon placed at `c` with ψ (the boat
  turns about its reference point, as in the boat step). The contact velocity is ignored. Pure kinematics; the
  physics is not run for predictions.
- `PredGap(A, B, H)`: the minimum hull gap over the samples 0, 0.1, …, H s.
- **Clearance margin** `m(A, B) = max(0.3 m, 0.05·L_max)`.

### 3.2 Clear astern, clear ahead, overlap

With `f_B = dir(ψ_B)` and `aft_B` = B's hull point with the smallest `dot(p, f_B)`:

- A is **clear astern of B** ⇔ every hull point p of A has `dot(p − aft_B, f_B) < 0`.
- A is **clear ahead of B** ⇔ B is clear astern of A.
- Otherwise they are **overlapped**. They are also overlapped (relation `overlapped_via`) when A is clear astern of B
  but some third racing boat C lies between them (`dot(c_C − c_A, c_C − c_B) < 0`) and overlaps both.
- The relation is only used when the terms apply (§1): same tack, or both `|twa| > 90°`, or rule 18 applies between
  them. Otherwise it is `n/a`.

### 3.3 Windward and leeward (same tack)

With `m̂ = unit(dir(ψ_A) + dir(ψ_B))` (the mean heading; if the headings are opposite, use `dir(ψ_A)`) and
`λ = cross(m̂, c_A − c_B)` (> 0: A is to the left of B):

- port tack (wind over the port side, leeward = starboard = right): A is **windward** of B ⇔ λ > 0;
- starboard tack: A is windward of B ⇔ λ < 0.
- `|λ| < 0.1 m` (in line): the boat farther upwind along the wind axis is windward (tie: lower boat index).

Using the mean heading makes the test symmetric and continuous when the two boats point in slightly different
directions.

### 3.4 Tacking (rule 13 state)

- A boat **passes head to wind** on the tick her tack label flips (`race.md` §0) while `|twa| < 90°`.
- From that tick she is **tacking** until `|twa| ≥ θ_CH − 5°` on the new tack, where θ_CH is her class's upwind VMG
  angle at the current true wind speed (`boat.md` polar), or until she flips back to the old tack (then she is
  simply back on it). A boat stuck head to wind after passing it stays tacking.
- Gybing is not a rule-13 state; a gybe only changes the tack label (via the boom, `race.md` §0).

### 3.5 Keep-clear test

For a pair where A must keep clear of B, each tick:

```
H_warn   = 4.0 s     H_breach = 1.0 s     δ = 10°  (δ_warn = 20°)    T_react = 0.5 s
course test:   PredGap(A, B, H) with both boats on their current motion
turn test:     only when overlapped: B's hull rotated by +δ and by −δ about her reference point and then moved
               T_react on the rotated heading; A on her current motion for T_react
state:
  a contact event between A and B from the last collision step         → Breach (contact)
  course test PredGap(H_breach) < m, or turn test (δ) hits A          → Breach
  course test PredGap(H_warn)   < m, or turn test (δ_warn) hits A      → Warning
  else                                                                → Clear
```

- The **course test** is the first half of the definition (B can sail her course without avoiding action); the
  **turn test** is the second half (overlapped: B can change course either way without immediate contact).
- `Breach` must persist to count (§9.1), except a contact, which counts at once.
- The warning is what the HUD shows as "keep clear" (`hud.md` §11); it never penalises.

### 3.6 Escape test (room to keep clear)

`Escape(A, B, H = 3 s)`: can A keep clear of B if she acts now? A tries four manoeuvres; B keeps her current motion:

1. hold course;
2. full turn to port: after a reaction delay of 0.3 s the helm moves from its current value `h` towards −1 at the
   class's `helm_rate`; the turn rate is `v / R(h)` with `R(h) = (turn_radius_full + turn_radius_offset)/|h| −
   turn_radius_offset` (`boat.md` §5.9); speed falls by the class's `rudder_drag_luff` / `rudder_drag_bear` table
   at that speed and helm (`boat.md` §4), whichever applies to the direction of the turn;
3. full turn to starboard, likewise towards +1;
4. slow down: after 0.3 s every sail is let fly, heading held, and the speed decays with the boat's deceleration law
   towards zero: `dv/dt = −(decel_linear·v + decel_const)` (`boat.md` §4, §5.8).

`Escape = true` if at least one manoeuvre keeps `PredGap > 0` (no contact) over H. The escape test is how the engine
decides whether a right-of-way boat gave the other boat **room** to keep clear (rules 15, 16) and whether a boat
could have given mark-room (rule 18) or room at an obstruction (rule 19).

### 3.7 Proper course estimate

For a boat heading to her next step with reference point `R` (for a gate: the buoy she is nearer to; for a line:
the nearest point of the line), with `β = compass(R − c)` and `θ_R = |wrap_pi(TWD − β)|` the true wind angle of the
direct course:

- `θ_R < θ_CH` (the mark is upwind of close-hauled): proper TWA = θ_CH (beat on the current tack);
- `θ_R > θ_DN` (below the downwind VMG angle θ_DN of the polar): proper TWA = θ_DN (run on the current tack);
- otherwise proper TWA = θ_R (sail straight at it).

The boat is **above her proper course** when `|twa| < proper TWA − 10°` for more than 2 s continuously (the 10°
covers wave and steering noise and the speed-building footing of real boats). This estimate is used by rule 17 and
by rule 18.4.

## 4. Right of way (Section A, rules 10–13) and its overrides

For every judged pair exactly one of the boats may hold an **obligation to keep clear** of the other, with a rule
code. The first matching line wins:

| # | Situation | Who keeps clear | Rule |
| --- | --- | --- | --- |
| 1 | One boat is a ghost or not racing | nobody (the ghost cannot interact, rule 24; `race.md` §6.3) | — |
| 2 | After the start signal, one boat is returning to start (OCS, OCS-I, or sailing towards the pre-start side to start) and the other is not | the returning boat, until she is completely on the pre-start side | 22.1 |
| 3 | One boat is taking a penalty turn (§9.3) and the other is not | the boat taking the penalty | 22.2 |
| 4 | One boat is tacking (§3.4) and the other is not | the tacking boat | 13 |
| 5 | Both are tacking | the one on the other's port side; if neither is on the other's port side, the one astern (the one whose reference point is behind along the mean heading) | 13 |
| 6 | Opposite tacks | the port-tack boat | 10 |
| 7 | Same tack, overlapped (§3.2) | the windward boat | 11 |
| 8 | Same tack, not overlapped | the boat clear astern | 12 |

"On the other's port side" for row 5: A's reference point is to the left of B's centreline (`left(c_A; stern_B → bow_B) > 0`)
while B's is not to the left of A's.

Rows 2 and 3 are the rule 22 duties: a boat that is putting a starting error right, or that is doing penalty turns,
keeps clear of everyone doing neither; between two such boats the normal rows apply.

The obligation is re-evaluated every tick. When it changes (who keeps clear, or the rule), the pair records the tick
and the cause (§5.2).

Rule 18 and 19 (§7) do not change this table: an inside boat that is windward still holds the rule-11 obligation,
but while she sails within the mark-room she is entitled to she is exonerated for breaking it (§6.1), and the outside
boat has the extra duty to give room.

## 5. Limits on the right-of-way boat (Section B, rules 14–17)

### 5.1 Rule 14: avoiding contact

In our words: every boat must avoid contact when she reasonably can. A right-of-way or room-entitled boat need not act until it is
clear that the other is not keeping clear or giving room, and is exonerated for a contact that causes no damage
(rule 21(c)).

Windmark: a contact is **damaging** when the contact event's `closing_speed` (`collisions.md` §5) is at least
`v_damage = 1.5 m/s`. For a damaging contact the right-of-way boat is also penalised under rule 14 if, during
the 2 s before the contact, she was in a pair state where the other boat was in `Breach` (§3.5) and she neither
changed heading by at least 10° nor reduced speed by at least 10 %. A non-damaging contact never penalises the
right-of-way boat under rule 14. The give-way boat is always penalised for a contact under her own obligation (unless
exonerated, §6.1).

### 5.2 Rule 15: acquiring right of way

A boat that becomes the right-of-way boat must at first give the other room to keep clear, unless she became
right-of-way boat because of the other boat's actions.

When an obligation "A keeps clear of B" begins (onset tick `t_on`, from no obligation or from the reverse), the
**cause** is recorded:

- **B's action** if B changed tack in the last 3 s (tacked or gybed onto the right-of-way tack), or B finished
  tacking (row 4 ended) in the last 3 s, or the relation changed because B went from clear astern of A to overlapped
  to leeward of A (B established a leeward overlap), or B stopped taking a penalty or completed her return to start;
- **A's action** otherwise (A tacked or gybed, A overtook, A's own course change).

If the cause is B's action, the engine runs `Escape(A, B)` at `t_on` and every tick until it is true once or 4 s have
passed. While it is false, B is in breach of rule 15 towards A, and A's keep-clear breaches towards B are exonerated
(rule 21(b), §6.1). As soon as it is true, B has given room and A's normal obligation applies.

### 5.3 Rule 16: changing course

**16.1**: a right-of-way boat that changes course must give the other boat room to keep clear.
**16.2**: on a beat, when a port-tack boat is keeping clear by sailing to pass astern of a starboard-tack boat, the
starboard-tack boat must not change course if that would make the port-tack boat immediately change course to go on
keeping clear.

A **course change** of boat B starts on the first tick her `turn_rate` has been above 3°/s in one direction for 0.3 s
(or her heading has changed by more than 5° in the last 1 s), and lasts until the rate has been below 1°/s for 1 s.

- **16.1**: if B (right of way over A) starts a course change at `t_c`, A was `Clear` or `Warning` (not `Breach`) at
  `t_c`, and within 3 s after `t_c` A becomes `Breach` while `Escape(A, B)` is false, B breaks rule 16.1 towards A.
  A's breaches in that window are exonerated. If `Escape` was true and A did not take it, A is in breach as usual.
- **16.2**: if A is on port and B on starboard, both upwind (`|twa| < 90°`), A is passing astern of B (A's predicted
  track over 5 s passes behind B's stern: at closest approach A's reference point is on the aft side of B's abeam line),
  and B starts a course change turning away from the wind (bearing away) at `t_c`, and within 3 s A becomes
  `Warning` or `Breach` where she was `Clear` before `t_c`, B breaks rule 16.2.

A course change that B makes to round a mark while sailing within her mark-room, or to avoid a third boat, is not
a breach (exonerated, §6.1).

### 5.4 Rule 17: same tack, proper course

A boat that comes from clear astern to overlapped within two hull lengths to leeward of a boat on the same tack must
not sail above her proper course while they stay overlapped on the same tack within that distance, unless she
promptly sails astern of the other; this does not apply if the overlap began while the windward boat was tacking.

- The pair gets the **rule-17 flag** (holder = the leeward boat A) on the tick the relation goes from "A clear
  astern of W" to "overlapped, A leeward", with `g(A, W) < 2·L_A`, same tack, and W not tacking.
- The flag clears when they are no longer overlapped, no longer on the same tack, or the gap exceeds `2·L_A`
  (hysteresis: clears at `2.2·L_A`).
- While flagged, A **breaks rule 17** when she is above her proper course (§3.7) and W is in `Warning` or `Breach`
  towards A. W's rule-11 breaches in that situation are exonerated (§6.1), and the incident is A's.

### 5.5 Precedence of breaches

On one tick a pair can show several breaches (for example W not keeping clear under rule 11 and A sailing above her
proper course under rule 17). The engine then keeps the one that the RRS makes decisive, in this order:
limitation breaches of the right-of-way boat (15, 16, 17, 18.3, 18.4, 14) first; they exonerate the give-way boat's
breach they caused; otherwise the give-way boat's keep-clear breach (10, 11, 12, 13, 22) or room breach (18.2, 19).

## 6. Section D: exoneration, starting errors, interference

### 6.1 Rule 21: exoneration

Windmark exonerates a boat for a breach (it is not penalised, and the incident goes to the other boat or to nobody)
when:

- **21(a)**: she was sailing within the room or mark-room she was entitled to (§7.4, §7.8) and her breach was of a
  Section A rule, rule 15 or rule 16 towards the boat that owed her that room;
- **21(b)**: she was compelled to break the rule by another boat's breach: her breach occurs while the other boat
  is in breach of 15, 16 or 17 towards her (§5), or less than 2 s after a contact the other boat was penalised for;
- **21(c)**: she is the right-of-way or room-entitled boat and broke rule 14 in a contact that was not damaging
  (§5.1).

### 6.2 Rule 22: starting errors and taking penalties

Covered by rows 2 and 3 of §4: a boat returning to start after the start signal, and a boat doing penalty turns,
keep clear of boats that are not. A boat returning to start is released from the duty when she is completely on
the pre-start side; a boat taking a penalty when the turn is complete or abandoned (§9.3).

### 6.3 Rule 24: interfering

Boats that are not racing (finished and cleared, retired, disqualified, disconnected) become ghosts (`race.md` §6.3)
and cannot interfere with racing boats at all. Windmark does not judge the other parts of rule 24.

## 7. Marks and obstructions (Section C, rules 18–20)

### 7.1 Zones

- The zone of a mark is a circle around the mark's centre with radius `Z = zone_lengths · L_near` (default 3 hull
  lengths, `courses.md` §5.2), with `L_near` the hull length of the boat nearer to the mark. For a single boat's own
  display the zone uses her own length.
- A boat is **in the zone** when any hull point is within `Z` of the mark centre.
- Each buoy of a gate has its own zone. Start and finish line ends are not rule-18 marks (see §7.10).
- The engine records per boat and mark the tick she entered the zone and whether she has left it since.

### 7.2 Rule 18.1: when rule 18 applies

Rule 18 applies between boats A and B at a mark M when:

- both are required to leave M on the same side, i.e. M is the current step of both (for a gate: both are heading
  for the same buoy, below), and
- at least one of them is in the zone,

and does not apply when:

- they are on opposite tacks and both on a beat to the mark (both `|twa| < 90°` and the mark bearing from each is
  within `θ_CH + 10°` of the wind direction), or
- one of them has already rounded M (her next step is past M) and the other has not (one approaching, one leaving),
- M is a start line end (never a rule-18 mark in Windmark; §7.10).

At a gate each boat is assigned the buoy she is heading for: the buoy whose bearing from her reference point is closer to her
course over ground, with a 10° hysteresis; rule 18 applies at a buoy between boats assigned to it.

When rule 18 applies between boats on opposite tacks, clear astern/ahead/overlap are used for them (§1).

### 7.3 Rule 18.2: giving mark-room

In our words: (a) when overlapped, the outside boat gives the inside boat mark-room; (b) if they are overlapped when
the first of them reaches the zone, the outside boat at that moment must go on giving mark-room even if the overlap
is later broken or a new one begins; if one is clear ahead when she reaches the zone, the boat clear astern at that
moment must give her mark-room; (c) that duty ends when the entitled boat leaves the zone or passes head to wind;
(d) when in reasonable doubt whether an overlap was made or broken in time, it is presumed that it was not.

Windmark:

1. **Status at the zone.** On the first tick either boat of a pair enters the zone of M while rule 18 applies, the
   pair's status for M is frozen:
   - overlapped → the **inside** boat is entitled, the outside one gives. Inside = the boat on the mark side of the
     other: for a mark to be left to port, the boat to the left along the mean heading (`λ > 0` with λ of §3.3, A
     relative to B); to starboard, the one to the right.
   - one clear ahead → the clear-ahead boat is entitled, the clear-astern boat gives.
   - **doubt (d)**: if the relation changed within the last 0.25 s (5 ticks) before that tick, the status is taken
     from before the change (an overlap made that late did not exist; an overlap broken that late still did).
2. The status holds (18.2(b)) until the entitled boat leaves the zone, passes head to wind, or has completed her
   rounding of M and has no hull point within `Z`; or rule 18 stops applying (§7.2). Then it is deleted.
3. **18.2(a) without a status.** If rule 18 applies, the boats are overlapped and there is no frozen status between
   them (for example after the status ended because the entitled boat tacked), the outside boat gives the inside
   boat mark-room, unless at the tick the overlap began `Room(G, E)` (below) was already impossible (the outside
   boat could not have given room from the time the overlap began); then no duty arises.

### 7.4 The mark-room test

For an entitled boat E, giver G and mark M with rounding side s:

- **Mark-room path** of E: from E's current pose, a path that goes straight to the entry tangent point of the
  **rounding circle** (centre M, radius `ρ = r_mark + 0.5·B_E + 0.25·L_E`), follows the circle in the rounding
  direction until the exit tangent towards the next step's reference point, then straight on. If E is closer to M
  than ρ, the circle is enlarged to her current distance. This is E's proper course at the mark in the room she is
  owed; a boat is not entitled to sail wider than this.
- **Mark-room corridor**: E's rules hull swept along the path, widened by `0.5·L_E` on each side.
- **Room(G, E)**: E moved along her mark-room path at her current speed for 4 s, G on her current motion:
  `Room = true` if the swept hulls stay at least `m(E, G)` apart.
- G **breaks rule 18.2** when `Room(G, E)` is false and `Escape(G, E)` shows that G could have kept the path free
  (at least one of G's manoeuvres keeps `Room` true); if G could not (E came in too fast or too late), there is no
  breach and E is expected to take what room exists.
- E is **within her mark-room** when her reference point is inside the corridor; her Section A, 15 and 16 breaches towards
  G are then exonerated (21(a)). Outside the corridor (sailing wide to push G away), she has no exoneration.

### 7.5 Rule 18.3: passing head to wind in the zone

In our words: if a boat in the zone passes head to wind from port to starboard tack and is then fetching the mark,
she must not make a boat that has been on starboard tack since entering the zone sail above close-hauled to avoid
contact, and she must give that boat mark-room if it becomes overlapped inside her; rule 18.2 then does not apply
between them.

Windmark: when boat T passes head to wind (§3.4) from port to starboard inside the zone of M, and afterwards is
fetching M (§7.6), then for every boat S that has been on starboard continuously since she entered the zone:

- the frozen 18.2 status between T and S is deleted;
- T **breaks rule 18.3** if `PredGap(T, S, 1.0 s) < m` with S holding her course while S is close-hauled
  (`|twa_S| ≤ θ_CH + 3°`), i.e. S would have to luff above close-hauled to avoid T;
- if S becomes overlapped inside T, S is entitled to mark-room from T (§7.4).

### 7.6 Fetching

A boat is **fetching** mark M (to be left to port or starboard) when, holding her current heading without tacking,
her reference point's straight track passes M on the required side at a distance ≤ `2·L`: the signed offset of M from the
track line `left(M; c → c + dir(cog))` has the required sign (mark to port ⇒ M to the left) and magnitude ≤ `2·L`,
and M is ahead (`dot(M − c, dir(cog)) > 0`), with `cog` the boat's course over ground (`boat.md` §5.10).

### 7.7 Rule 18.4: gybing at a mark

In our words: when an inside overlapped right-of-way boat must gybe at a mark to sail her proper course, until she
gybes she must sail no farther from the mark than needed to sail that course.

Windmark: when E is entitled under 18.2, has right of way over G (§4), is on a downwind leg (`|twa| > 90°`), and the
next leg's proper course needs the other tack (the course turns through the wind at M), E **breaks rule 18.4**
towards G if, while overlapped with G and before her tack label changes, her distance to M exceeds
`d_min + 1.0·L_E`, where `d_min` is the smallest distance she has had to M since entering the zone.

### 7.8 Rule 19: room to pass an obstruction

In our words: when boats are overlapped at an obstruction, the outside boat must give the inside boat room between
her and the obstruction, unless she has been unable to do so since the overlap began. (When the right-of-way boat
chooses which side to pass, the other has to follow.)

Windmark (simplified, `full` rules only):

- Obstructions: land and shallows from the venue, the course's exclusion zones, anchored committee and mark boats
  that are not a mark of the boats' current leg, and any course object that is not a mark for them.
- Rule 19 applies between overlapped boats on the same tack when, for both, `PredGap(boat, obstruction, 6 s)` on
  their current motion is below `1.0·L` and they would pass the obstruction on the same side (the obstruction's
  nearest point is on the same side of both boats' tracks).
- The inside boat I (nearer the obstruction) is entitled to **room**: her path is her current heading deflected away
  from the obstruction just enough to keep `0.5·B_I + 0.25·L_I` from it. The outside boat G breaks rule 19 if
  `Room(G, I)` over 4 s along that path is false while G could have kept it free (`Escape` as in §7.4).
- At a starting mark (the committee boat or pin) from the time boats are approaching the line to start until they
  have passed it, rule 19 does not apply (no room at the committee boat for a boat squeezing in to windward).
- Continuous obstructions (long shorelines) are handled by the same test per tick.

### 7.9 Rule 20: room to tack at an obstruction (optional, off by default)

In our words: a close-hauled boat approaching an obstruction may hail for room to tack; the hailed boat must either
tack or reply "you tack", and the hailing boat must then tack as soon as possible. The hail is not allowed when the
hailing boat could avoid the obstruction by bearing away safely, or at a mark the hailed boat is fetching.

When enabled (`rules_hail = on`), a player has a **Hail: room to tack** action (`hud.md` §11). The AI answers
automatically. The server checks:

- valid hail: the hailing boat H is close-hauled (`|twa| ≤ θ_CH + 5°`), `PredGap(H, obstruction, 6 s) < 1.0·L_H`, a boat
  S on the same tack is to windward of H within `3·L` and would be hit if H tacked (H's tack path, simulated as a
  turn at her minimum radius, comes within `m` of S);
- S must, within 3 s, either start tacking (`tacking` flag) or press **Reply: you tack**; after the reply S must give
  H room to tack and avoid her; if S does neither, S breaks rule 20;
- an invalid hail (H could bear away clear, or S is fetching a mark) makes H break rule 20 if S tacks in response.

This is a Phase 2 feature; the core must accept the hail inputs but may treat them as no-ops until implemented.

### 7.10 Start and finish line ends

The committee boat and the pin are starting marks: rule 18 does not apply at them, and rule 19 does not apply at them
while boats are approaching to start (§7.8). A windward boat that squeezes between a leeward boat and the committee
boat ("barging") has no room and keeps clear under rule 11. Finishing marks: Windmark v1 does not apply rule 18 at
finish line ends; they are obstructions under §7.8 once the boats are not approaching to start. (Known
simplification; list it in the in-game rules help.)

## 8. Rule 31: touching a mark, and course boundaries

In our words: while racing, a boat must not touch a starting mark before starting, a mark that begins, bounds or
ends the leg she is sailing, or a finishing mark after finishing.

Windmark: a contact event (`collisions.md` §5) with `other_kind` = `mark` or `course_object` and **`begin` = true**
is a **mark touch** when that course object (`other` = its index in the course's `marks`, `courses.md` §2) is:

- a start line end, and the boat has not started;
- a buoy of step k−1 or step k for her current next step k (the marks that begin and end her leg; both buoys of a
  gate);
- a finish line end, after she finished and before she cleared the finish.

A mark touch gives a one-turn penalty (rule 44.1(a)), code `31`, whatever the `penalty` setting. Exoneration: when
the touch happens less than 2 s after (or during) another boat's breach towards her (21(b)), that boat's incident is
opened instead and the touch is not penalised. One mark-touch penalty per mark per 10 s at most.

Boundaries (`courses.md` §5.1, rule code `SI-boundary`): warning, then a one-turn penalty after 15 s outside, then
disqualification after 60 s. These are sailing-instruction penalties, not RRS rules.

## 9. Penalties

### 9.1 Incidents

An **incident** is the unit that gets at most one penalty per boat:

- It opens on a pair when a counted breach occurs: a contact between them (a boat–boat contact event with
  `begin` = true; a contact that continues over several ticks is one contact), or a non-contact breach that has
  persisted for `T_persist` (standard umpire: 0.5 s for rules 10, 13, 15, 16, 18.3, 22; 1.0 s for rules 11, 12, 17,
  18.2, 18.4, 19).
- It records the culprit: the boat whose breach is decisive after exoneration and precedence (§5.5, §6.1).
- It closes after the pair has been in `Clear` (no warning, no breach, no contact) for 5 s continuously, or when the
  pair drops out of range (§2.1).
- While it is open, further breaches between the pair give no new penalty, except a **contact** after a non-contact
  penalty: if the culprit of the open incident was penalised without contact and the boats then touch with the same
  culprit at fault, no second penalty; if the other boat is at fault for the contact, she gets her own penalty.
- A boat gets at most one new penalty per 3 s from all incidents together (a chain reaction in a crowded start is
  judged on its first decisive breach).

### 9.2 Issuing a penalty

The culprit receives a **turn penalty** `{rule, other boat, tick, count}` with `count` = 1 turn (`one_turn`, the
default, and always for rule 31) or 2 turns (`two_turns`, the RRS default for Part 2 breaches under rule 44.2). Events
go to both boats and the fleet feed (`hud.md` §11). A boat may hold several pending penalties; they are taken one at a
time, in order.

Scoring penalties: the Z flag (`race.md` §3.3) is a scoring penalty and needs no turn.

### 9.3 Taking a penalty turn (rule 44.2)

In our words: to take the penalty a boat sails well clear of other boats as soon as possible after the incident and
promptly makes the required number of turns in the same direction, each including one tack and one gybe; near the
finishing line she must be completely on the course side before she finishes.

Windmark turn tracker, per boat with a pending penalty:

- **Turning**: the tracker integrates the heading change `Θ += wrap_pi(ψ − ψ_prev)` while the boat keeps turning in one
  direction: `|r| ≥ 2°/s` in that direction. A turn **starts** when that has held for 0.5 s; a pause (`|r| < 2°/s`) of
  more than 3 s, or a reversal of more than 20° from the extreme reached, **resets** the turn (Θ = 0).
- It counts **tacks** (passing head to wind: `twa` changes sign with `|twa| < 90°`) and **gybes** (`twa` changes sign
  with `|twa| > 90°`) that
  happen during the turn in the turn's direction.
- **One turn done** when `|Θ| ≥ 350°` with at least one tack and one gybe (the 10° margin absorbs wind shifts during
  the turn). Two-turns penalty: `|Θ| ≥ 710°` with two tacks and two gybes, in one continuous turn.
- **Where**: the turn only counts if the boat's hull stays outside the zone of the mark she is heading for and of the
  mark she last rounded for the whole turn; entering such a zone resets it. Rounding a mark during a turn resets it.
  (This stops a mark rounding from being used as half a penalty.)
- **Before the start**: a penalty from a pre-start incident may be taken before the start signal.
- **Finishing**: a boat with a pending penalty cannot finish (`race.md` §6.1).
- While the tracker has a turn in progress the boat is **taking a penalty** for rule 22.2 (§4 row 3).
- When the turn is done, the oldest pending penalty is removed (event `PenaltyServed`).

### 9.4 Deadline

A pending penalty must be served within `T_serve = 45 s` (fleet) of the later of: the penalty, or the moment the
previous penalty of the same boat was served. If the deadline passes with no turn in progress, the boat receives an
extra one-turn penalty with code `44.1-late` and the deadline restarts. The HUD shows the countdown (`hud.md` §12).
This is a Windmark simplification of the RRS "as soon as possible" that a program can enforce.

### 9.5 Disqualification

A boat is disqualified (`DSQ`, `race.md` §9) when she holds `dsq_pending = 3` unserved turn penalties at once, or
has received `dsq_total = 6` penalties in the race. She becomes a ghost at once. Both limits are lobby settings; AI
boats obey them like humans.

### 9.6 Match races (Appendix C, simplified)

- Penalties are issued as in fleet racing (the automatic umpire replaces the on-water umpires).
- A penalised boat may delay her penalty: with **one** pending penalty there is no deadline, but she must take it
  before finishing; with **two**, she must take one promptly: the §9.4 deadline applies with `T_serve = 15 s`
  (missing it adds a `44.1-late` penalty), and the fleet `dsq_pending = 3` applies.
- **Offsetting**: when both boats hold a pending penalty, one of each is cancelled at once (event
  `PenaltyCancelled`).
- The pre-start entry penalties (`C-prep`, `C-entry`, `race.md` §3.4) are turn penalties taken after the start signal.
- Rule 17 does not apply in match races (two boats alone; the proper-course limit is dropped), and 18.2 applies as
  in fleet racing.

## 10. Umpire modes and protests

`umpire` setting (`race.md` §2):

| Mode | Behaviour |
| --- | --- |
| `standard` (default) | Contacts and persisted non-contact breaches (§9.1) are penalised automatically. |
| `contact_only` | Only contacts and mark touches are penalised; non-contact breaches show warnings, except rules 10, 13 and 22, which are still penalised after 1.0 s. Friendlier for new players. |
| `protest` | Private lobbies. Contacts and mark touches as `standard`. A non-contact breach opens a **protestable incident**: the boat that was fouled gets a prompt for 8 s (`hud.md` §11); if she protests, the culprit receives the penalty the engine determined; if not, nothing happens. AI boats protest when the minimum hull gap during the incident was below `0.5·m`. |

There is no hearing, redress or appeal: the engine's verdict is final and the same for every client (online there is
exactly one verdict, made by the server, `networking.md` §10).

## 11. Published records and events

### 11.1 Per pair (for the HUD radar, the AI and the network)

```
PairRecord {
  i, j                        boat indices, i < j
  relation                    i clear astern of j / clear ahead / overlapped / overlapped_via / n_a
  keep_clear                  none | (giver, holder, rule)          rule ∈ {10, 11, 12, 13, 22.1, 22.2}
  kc_state                    Clear | Warning | Breach (§3.5)
  room                        none | (entitled, giver, rule, mark or obstruction id)   rule ∈ {18.2, 18.3, 19}
  room_state                  Clear | Warning (Room false for 4 s but G can still act) | Breach
  limits                      set of (holder, rule) the right-of-way boat is breaking now: 15, 16.1, 16.2, 17, 18.4, 14
  rule17_flag                 holder or none
  incident                    none | (culprit, rule, opened_tick)
  gap_m, ttc_s                hull gap now; predicted time to contact on current motion (∞ if none within 10 s)
}
```

### 11.2 Per boat

```
BoatRules {
  tack, tacking, turning_for_penalty, turn_progress_deg, turn_tacks, turn_gybes
  pending_penalties [ {rule, other, tick, count} ], served_count, received_count
  deadline_s                  seconds to the §9.4 deadline, or none
  zones [ {mark_step, in_zone, entered_tick} ]
  returning_to_start          (race.md §4.3)
  dsq                         bool
}
```

### 11.3 Events

| Event | Data |
| --- | --- |
| `RuleWarning` | holder, other, rule (rising edge of `Warning` for the give-way boat) |
| `Incident` | culprit, other, rule, contact yes/no |
| `Penalty` | boat, rule, other, count, tick |
| `PenaltyServed` | boat, rule |
| `PenaltyCancelled` | boat, rule (match offsetting) |
| `PenaltyLate` | boat (the `44.1-late` penalty) |
| `MarkTouch` | boat, mark id |
| `Protestable` / `Protested` | fouled boat, culprit, rule, deadline (protest mode) |
| `Hail` / `HailReply` | boat, kind (rule 20, optional) |
| `Disqualified` | boat, reason (`dsq_pending`, `dsq_total`, boundary) |

Rule codes in events are strings: `"10"`, `"11"`, `"12"`, `"13"`, `"14"`, `"15"`, `"16.1"`, `"16.2"`, `"17"`,
`"18.2"`, `"18.3"`, `"18.4"`, `"19"`, `"20"`, `"22.1"`, `"22.2"`, `"31"`, `"44.1-late"`, `"C-prep"`, `"C-entry"`,
`"SI-boundary"`. The HUD maps each code to a short text (`hud.md` §12).

## 12. Parameters

| Name | Value | Where |
| --- | --- | --- |
| `R_pair` | 10 L_max | §2.1 |
| margin `m` | max(0.3 m, 0.05 L_max) | §3.1 |
| prediction sub-step | 0.1 s | §3.1 |
| `H_warn`, `H_breach` | 4.0 s, 1.0 s | §3.5 |
| turn test δ / δ_warn, reaction | 10° / 20°, 0.5 s | §3.5 |
| escape horizon, reaction | 3 s, 0.3 s | §3.6 |
| proper-course tolerance | 10°, 2 s | §3.7 |
| rule 15 window | 3 s cause, 4 s room | §5.2 |
| course change detect | > 3°/s for 0.3 s; end < 1°/s for 1 s | §5.3 |
| rule 16 window | 3 s | §5.3 |
| rule 17 distance | 2 L (clear at 2.2 L) | §5.4 |
| `v_damage` | 1.5 m/s | §5.1 |
| zone | 3 L | §7.1 |
| overlap doubt window | 0.25 s | §7.3 |
| rounding circle | r_mark + 0.5 B + 0.25 L | §7.4 |
| corridor half-width | 0.5 L | §7.4 |
| `T_persist` | 0.5 s / 1.0 s | §9.1 |
| incident close | 5 s clear | §9.1 |
| per-boat penalty spacing | 3 s | §9.1 |
| turn tracker | 2°/s, start 0.5 s, pause 3 s, reversal 20°, 350° / 710° | §9.3 |
| `T_serve` | 45 s fleet, 15 s match with two pending | §9.4, §9.6 |
| `dsq_pending`, `dsq_total` | 3, 6 | §9.5 |
| protest prompt | 8 s | §10 |

All are constants of the rules module with these defaults, loadable from the race settings for testing; changing
them changes the game's behaviour, so the spec is updated first.

## 13. Tests

Scenario tests (two or three scripted boats, headless) with the expected obligation, states and penalties:

- Port–starboard crossing on a beat: port boat ducks (Clear), port boat crosses 0.5 L ahead (Warning, no penalty),
  port boat forces starboard to bear away (Breach persisted → penalty rule 10), collision → penalty rule 10.
- Starboard boat bears away onto a ducking port boat (16.2) and luffs into a port boat crossing ahead (16.1 when the
  port boat had no escape; rule 10 when she had one and did not take it).
- Tack too close: a boat tacks onto starboard 1 L ahead of a port-tack boat so that the port boat cannot avoid her
  → rule 13 while she is tacking; if she completes the tack and the port boat still has no escape → rule 15 against
  the tacker (cause = her action).
- Leeward boat from clear astern within 2 L luffs above proper course → rule 17; the same boat establishing leeward
  from 3 L away may luff (no flag).
- Windward mark, port rounding: overlapped at the zone, outside boat squeezes the inside → 18.2; inside boat sails
  wide outside her corridor and contacts → no exoneration; clear-astern boat at the zone gets an inside overlap late
  → no mark-room; boat tacks inside the zone onto starboard and forces a starboard boat above close-hauled → 18.3.
- Barging at the committee boat → windward boat penalised under 11, no room.
- OCS returner hits a starting boat → 22.1; boat doing a penalty turn hits another → 22.2.
- Penalty turn: a 360 with a tack and a gybe serves it; 360 with a pause of 4 s does not; a turn inside the zone of
  the next mark does not; deadline passes → `44.1-late`; three pending → DSQ.
- Mark touch of the next mark → one-turn penalty; touch of an unrelated mark → none.
- Determinism: the same scenario gives the same records and events bit for bit on all supported platforms.
