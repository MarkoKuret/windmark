# "Who's wrong?" quiz scenarios 1 to 4

The first four weekly rules quizzes (`social_plan.md` §5 to §7, backlog WM-073). Each is a scenario file in
`game/data/scenarios/` (`race.md` §14, `data_format.md` §9): the same 25 s clip every run, paused at the end, reset
replays it. The engine's call for each is checked headlessly by `game/tests/run_scenario_test.sh` (one penalty, the
boat, the rule, the clip time). Rule numbers and wording are those of the RRS 2025-2028 as `docs/specs/rules.md`
explains them. **The owner checks every answer against `rules.md` and the RRS before it is posted.**

Common to all four: wm7 sportsboats, 12 kn steady wind from the north (0°), no puffs, the practice waters
windward-leeward course (windward mark "w" left to port). Clip time 0 is the set-up; times below are clip time as
the scenario counts it. Boat 0 is the one the cameras start on.

Capture: run the command, let it play to about the freeze time, press `.` for the clean pause (no "Paused" label),
F10 hides the HUD for a clean still; `,` gives slow motion for the incident. The answer post plays on through the
call so the HUD shows the rule text.

The HUD texts: for the viewed boat a 4 s banner `PENALTY: <rule text> (<other boat>)`; for another boat a feed line
`<boat> penalised, rule <n> (<other>)` (`hud.md` §12.2, §12.3).

---

## 1. Port meets starboard (rule 10)

`godot --path game res://scenes/sail_test.tscn -- --scenario=port_starboard`

- **Set-up.** Kestrel (7, boat 0) close-hauled on starboard and Sirocco (23, boat 1) close-hauled on port, 300 m up
  the first beat, sailing straight at the same point. Neither changes course.
- **Freeze frame:** 18.0 s. The two bows about 5 m apart, Sirocco on port about to cross Kestrel's bow.
- **Engine's call:** Sirocco penalised, rule 10, at 18.6 s (the keep-clear warning shows from 15.2 s). They collide
  at 19.2 s.
- **HUD rule text:** `Port tack keeps clear of starboard`; feed line `Sirocco penalised, rule 10 (Kestrel)`.
- **Answer text:** Sirocco is wrong. She is on port tack (the wind comes over her left side), Kestrel is on
  starboard, and a port-tack boat must keep clear of a starboard-tack boat. Sirocco had to tack or bear away behind
  Kestrel in good time. Penalty: Sirocco, one 360° turn.
- **Rule:** RRS 10, On Opposite Tacks: when boats are on opposite tacks, a port-tack boat shall keep clear of a
  starboard-tack boat.
- **Trap.** "Kestrel should have avoided her": rule 14 asks every boat to avoid contact if reasonably possible, but a
  right-of-way boat need not act until it is clear the other is not keeping clear, and Kestrel is only penalised
  for not avoiding a contact that causes damage. "Kestrel changed course": she did not, she held her course
  throughout (rule 16 is not in play). **Owner check:** this clip ends in a hard collision (about 3.9 m/s closing).
  A strict protest committee could also ask whether Kestrel could have avoided it under rule 14; the engine does not
  penalise her (see the engine notes in backlog WM-073). Cut the answer clip at the contact or before it.

## 2. Clear astern (rule 12)

`godot --path game res://scenes/sail_test.tscn -- --scenario=clear_astern`

- **Set-up.** Firecrest (345, boat 0) and Swift (219, boat 1) both close-hauled on starboard on the first beat,
  in line on the same course, Swift a few metres behind. Firecrest sails with no jib (lost it, or dropped it) and is
  about 0.3 m/s slower. Swift holds her course and closes on Firecrest's transom.
- **Freeze frame:** 17.0 s. Swift's bow under a metre from Firecrest's transom, both on the same heading.
- **Engine's call:** Swift penalised, rule 12, at 19.0 s (the warning shows from 14.6 s). Swift's bow touches
  Firecrest's stern at 20.5 s, softly (no damage).
- **HUD rule text:** `Boat clear astern keeps clear`; feed line `Swift penalised, rule 12 (Firecrest)`.
- **Answer text:** Swift is wrong. Both boats are on the same tack and not overlapped: Swift is clear astern, and a
  boat clear astern must keep clear of the boat clear ahead. It does not matter that Firecrest is slow; Swift had
  all the time in the world to sail round her or ease off. Penalty: Swift, one 360° turn.
- **Rule:** RRS 12, On the Same Tack, Not Overlapped: when boats are on the same tack and not overlapped, a boat
  clear astern shall keep clear of a boat clear ahead.
- **Trap.** "Firecrest slowed down in front of her (brake test)": slowing down is not a course change, so rule 16
  does not limit it, and she did not slow suddenly, she was simply slower all along. "Swift was overlapping at the
  end": the overlap only begins at the contact, after the incident; until then Swift is clear astern (her bow is
  behind a line abeam from Firecrest's transom). After the contact Swift ends up overlapped to leeward, which gives
  her right of way under rule 11 only from then on and only with rule 15 (she must first give Firecrest room).

## 3. Mark-room at the zone (rule 18.2)

`godot --path game res://scenes/sail_test.tscn -- --scenario=mark_room`

- **Set-up.** Both boats on starboard on the layline to the windward mark, which is left to port. Halcyon (51,
  boat 1) is inside (to leeward, nearer the mark), Petrel (88, boat 0) outside (to windward), her bow about a metre
  ahead; they are overlapped all the way in. At 11.5 s the first of them reaches the zone (three hull lengths)
  overlapped. Petrel bears away round the mark at 18.5 s, early, across Halcyon's bow; Halcyon bears away at the
  mark at 19.8 s.
- **Freeze frame:** 19.5 s. Petrel already turning down round the mark, Halcyon abeam the mark on the inside, about
  2 m between them.
- **Engine's call:** Petrel penalised, rule 18.2, at 20.9 s (a rule 11 warning shows from 18.8 s). The boats touch
  at 21.35 s, softly (no damage).
- **HUD rule text:** `Give mark-room`; banner on Petrel `PENALTY: Give mark-room (Halcyon)`.
- **Answer text:** Petrel is wrong. When the first of the two boats reached the zone they were overlapped, so the
  outside boat (Petrel) had to give the inside boat (Halcyon) mark-room from then on: room to sail to the mark and
  round it. Petrel turned down round the mark across Halcyon's bow and took that room away. Being a little ahead and
  getting to the mark first does not help her: what counts is the overlap at the zone. Penalty: Petrel, one 360°
  turn.
- **Rule:** RRS 18.2(a)(1), Giving Mark-Room: when the first of two boats reaches the zone, if they are overlapped,
  the outside boat at that moment shall give the inside boat mark-room (and keeps doing so while rule 18 applies,
  rule 18.2(a)).
- **Trap.** "Petrel was ahead, she got there first": reaching the zone first only decides it when the boats are not
  overlapped (18.2(a)(2)); here they were. "It's just rule 11, windward keeps clear": true too (Petrel is windward,
  and breaks rule 11 as well), but the rule that makes the mark special is 18.2, and it is the one the umpire cites;
  it would protect Halcyon even if she were the windward boat. "Halcyon sailed too wide": no, she bears away at the
  mark on her own proper course, inside the room she is owed.

## 4. Tacking in the zone (rule 18.3)

`godot --path game res://scenes/sail_test.tscn -- --scenario=tack_in_zone`

- **Set-up.** Mistral (404, boat 1) is close-hauled on starboard on the layline, fetching the windward mark (left to
  port); she has been on starboard since she entered the zone. Bora (610, boat 0) comes in on port from the left,
  short of Mistral's course, and tacks onto starboard at 13.0 s inside the zone (head to wind about 15.3 s, tack
  done about 17.3 s), just ahead and to leeward of Mistral's course. Bora comes out of the tack slow; Mistral closes
  from astern and has to luff above close-hauled (she luffs from 18.8 s).
- **Freeze frame:** 17.5 s. Bora has just finished her tack, on starboard and slow, Mistral about 1.3 m behind her
  and closing.
- **Engine's call:** Bora penalised, rule 18.3, at 18.7 s (a rule 10 warning while Bora is on port from 12.85 s,
  rule 13 while she tacks). No contact: Mistral luffs clear.
- **HUD rule text:** `Tacked in the zone: keep clear`; banner on Bora `PENALTY: Tacked in the zone: keep clear
  (Mistral)`.
- **Answer text:** Bora is wrong. She tacked from port to starboard inside the zone of a mark left to port, and
  Mistral, on starboard and fetching the mark, had been on starboard since she entered the zone. A boat that tacks
  there must not make the other boat sail above close-hauled to avoid her, and Bora did exactly that: Mistral had
  to luff to miss her stern. Once Bora finished her tack she was clear ahead, but in the zone that does not save
  her. Penalty: Bora, one 360° turn.
- **Rule:** RRS 18.3, Tacking in the Zone: if a boat passes head to wind from port to starboard in the zone of a
  mark to be left to port, rule 18.2 does not apply between her and a starboard boat fetching the mark; if that boat
  has been on starboard since entering the zone, the tacking boat shall not cause her to sail above close-hauled to
  avoid contact (and shall give her mark-room if she becomes overlapped inside).
- **Trap.** "Bora completed her tack, she's clear ahead, rule 12 says Mistral keeps clear": rule 12 does give Bora
  right of way, but 18.3 limits it; and rule 15 also asks a boat that gains right of way by tacking to give the
  other room to keep clear. "Rule 13, she was still tacking": no, the tack was complete (close-hauled) before
  Mistral had to luff; this is not a rule 13 foul. "Mistral could have borne away": not without hitting Bora or
  going inside the mark; luffing was her only way out. "18.3 is gone in the new rules": it was rewritten for
  2025-2028, not removed.
