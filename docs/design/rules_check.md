# Rules check against the racing rules in force (WM-087)

Research and proposal; the owner decided on 2026-10-05 (WM-095) and the decisions are implemented in
`docs/specs/rules.md`, `race.md`, `ai.md`, `hud.md` and the core: see §4 for each item and its status. The rules are
referred to by number and described in our own words; no rule text is reproduced.

Checked on 2026-10-05 against `docs/specs/rules.md`, `docs/specs/race.md` and `core/src/rules/` (`rules.cpp`) and
`core/src/race/race.cpp` where behaviour matters.

## 1. Edition in force

- **The Racing Rules of Sailing 2025-2028** (World Sailing), in effect since 1 January 2025 and valid until
  31 December 2028. World Sailing's racing rules page names it as the current edition.
- **Changes and Corrections, Version 2** is the latest World Sailing amendment found (no Version 3 as of this check):
  - effective **1 January 2025** (agreed after the book was printed in June 2024): the definitions *Obstruction*
    and *Proper Course* were rewritten, plus changes in Part 5 (rule 60.5(c)(4)) and Appendices D, F and J, and
    editorial corrections (27.3, 32.3, 63.1, 63.3, 69.2, sail letters and others);
  - effective **20 April 2026**: two corrections only (A6.1 punctuation, E6.3 radio sailing protests). Nothing
    that touches Windmark.
  - World Sailing publishes a consolidated text with these changes (April 2026 PDF).
- **Case Book 2025-2028** (version 2025-07) holds the interpretations used below (Cases 108 and 149 on penalty
  turns).
- `rules.md` and `race.md` say they follow the 2021-2024 edition. In places they actually follow the 2017-2020
  numbering (Section D, exoneration; see row D2), so some references are two editions old.

### What changed from 2021-2024 to 2025-2028 (the parts that matter to Windmark)

| Area | Change, in our words |
| --- | --- |
| Definitions | New *Continuing Obstruction* (an obstruction the shortest boat involved passes alongside for at least three of her lengths; not a vessel under way, a racing boat, or a committee vessel that is a mark). *Mark-Room* shortened to three parts: room to sail to the mark when her proper course is close to it, to round or pass it on the required side, and to leave it astern; the old remark about room to tack is gone. *Obstruction* (as amended 1 Jan 2025): an object she could not pass without a substantial course change from one length away, an object that can be passed safely on one side only, or an object, area or line a rule designates as one. *Proper Course* (as amended 1 Jan 2025): the course she would choose to sail the course as quickly as possible without the other boats involved; still none before her starting signal. *Finish* no longer needs a start, and absorbs the old 28.1 wording. *Sail the Course* now contains starting, the string test (including gates) and finishing. New *Committee*. |
| Rule 14 | Besides avoiding contact herself, a boat must not, where she reasonably can avoid it, cause contact between two other boats, or between a boat and an object that should be avoided. |
| Rule 17 | The exception for an overlap that begins while the windward boat is tacking was deleted. |
| Rule 18 | 18.1 renumbered ((a)(1) to (a)(4), (b)). 18.2 restructured: at the moment the first of two boats reaches the zone, if overlapped the outside boat owes the inside boat mark-room; if not overlapped, **the boat not yet in the zone** owes mark-room (before: the boat clear astern). The 2021 18.2(c)(2) (a giver that becomes inside must also give room for the proper course) was dropped. 18.3 now: at a port-hand mark, a boat that tacks from port to starboard in the zone loses her 18.2 entitlement towards a starboard boat that is **fetching** the mark (before: the tacker had to be fetching), and owes the starboard boat the 18.3 duties if that boat has been on starboard since entering the zone. |
| Rule 19 | 19.2(a): a right-of-way boat that changes course while choosing her side of an obstruction must give the other boat room to keep clear (and this breach is not exonerable like 16.1). |
| Rule 20 | The hail is now the specific words "Room to tack". |
| Section C preamble | The starting-mark exception now lasts until the boats have left the mark astern (before: passed it). |
| Rule 44.3, 30.2 | Scoring Penalty only if the notice of race or sailing instructions says so; it is in points, 20 % of the Did Not Finish score, rounded to the nearest tenth (before: nearest whole point). |
| Unchanged | Rules 10 to 13, 15, 16, 21 (starting errors, penalties, backing a sail), 23, 26, 28, 29, 30.1, 30.3, 30.4, 31, 43 and 44.1, 44.2 (Two-Turns for Part 2, One-Turn for rule 31, "well clear as soon as possible, then promptly"). |

## 2. Differences

Kinds: **missing** (the rule exists, Windmark does not judge it), **different** (Windmark judges it, but not as the
rule says, and the spec does not say so), **simplification** (already documented as a Windmark simplification),
**outdated** (follows an older edition).

### 2.1 References, definitions

| # | Rule | Current rules (our words) | Windmark now | Kind | Gameplay impact | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | Edition | 2025-2028 with Changes and Corrections v2. | `rules.md` intro and `race.md` intro cite 2021-2024. | outdated | None by itself. | **Follow**: cite 2025-2028 once the decisions below are made. |
| D2 | Section D, rule 43 | Since 2021: 21 = starting errors, taking penalties, backing a sail (21.1, 21.2, 21.3); 22 = capsized, anchored, aground, rescuing; 23 = interfering; exoneration is rule 43.1(a) compelled, (b) within room or mark-room, (c) right-of-way or room boat and a contact without damage or injury. | `rules.md` §6 and the event codes use the 2017-2020 numbers: exoneration "21(a)(b)(c)", rule "22.1" / "22.2" for returning and penalty boats, rule 24 interfering (`rules.cpp` `rule_name`). | outdated | Players and the HUD see wrong rule numbers in the fleet feed and penalty messages. | **Follow**: codes `21.1`, `21.2`; cite 43.1 for exoneration and 23 for interfering. Small rename, touches HUD text and the event code table (`rules.md` §11). |
| D3 | Clear astern, clear ahead, overlap | Measured on hull **and equipment in normal position** (bowsprit, pole). Terms apply on the same tack, or on opposite tacks when rule 18 applies or both are more than 90° from the true wind. | Hull outline only (`race.md` §0 rules hull; sprits are not in the collision outline, `collisions.md` §2). The tack conditions match. | different | A boat with a sprit set gets her overlap later by the sprit length (about 1 to 2 m on wm12): marginal at zone entry and in luffing. | **Simplification**: keep, write it into §1; reconsider if sprits get longer. |
| D4 | Keep clear | Right-of-way boat can hold her course with no avoiding action and, when overlapped, can change course both ways without immediate contact. | Same two halves, measured by prediction (4 s / 1 s, 10° turn test, §3.5). | simplification | None: this is the measurement. | **Keep**. |
| D5 | Zone | Three hull lengths of the boat nearer the mark, measured from the mark; in the zone when any part of the hull is in it. | Circle of 3 L around the mark **centre** (§7.1). | different | Buoys: negligible. A mark boat or large object used as a rounding mark gets a zone smaller by its radius. | **Follow**: radius `Z + r_mark` (cheap). |
| D6 | Mark-Room | Room to sail to the mark when the proper course is close to it, to round or pass it on the required side, and to leave it astern. No built-in room to tack. | §1 wording is from older editions ("then her proper course while at the mark", plus the room-to-tack clause). The path test (§7.4: to the rounding circle, round, exit tangent) already matches the three parts. | outdated (wording) | None: behaviour already close. | **Follow**: rewrite the §1 row. |
| D7 | Proper Course | The course she would choose to sail the course as quickly as possible without the other boats involved. **No proper course before her starting signal.** | §3.7 estimate towards the next step, and **before the start towards the line midpoint** (`rules.cpp` proper-course block), so "above proper course" is live in the pre-start. | different | Rule 17 (and 18.4) can penalise a leeward boat luffing in the pre-start, which the rules do not stop (only 15 and 16 limit her there). Affects every start with luffing. | **Follow**: no "above proper course" before the starting signal. |
| D8 | Obstruction | As amended 1 Jan 2025 (see §1). A racing boat is an obstruction only to boats that must keep clear of her or avoid her. | Land, shallows, exclusion zones, anchored committee and mark boats that are not a mark of the leg (§7.8). | matches | None. | **Keep**. |
| D9 | Continuing Obstruction | New: 3 hull lengths of the shortest boat alongside; rule 19 always applies there and rule 18 does not; 19.2(c) (no room for a boat that came from clear astern into a gap that did not exist). | No such notion; shorelines judged tick by tick (§7.8). | missing | Only venues with shores or breakwaters on the course. | **Simplification**: keep for v1, add to §7.8. |
| D10 | Finish | Hull crosses from the course side after her starting signal; she need not have started; a boat that then takes a penalty has not finished at that crossing. | A boat with a pending penalty cannot finish (`race.md` §6.1). OCS boats released onto the course finish and score OCS. | simplification | Clear for players: the line will not take you with a penalty. | **Keep** (document that the RRS would let her cross and be protested). |
| D11 | Racing | From the preparatory signal until she finishes and clears the line and marks (or retires, or a recall, postponement or abandonment). | Prep signal to 10 s after finishing or 2 L beyond the line; rules not live after a recall until the new prep signal. | simplification | None. | **Keep**. |

### 2.2 Part 2: when boats meet

| # | Rule | Current rules (our words) | Windmark now | Kind | Gameplay impact | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | 10, 11, 12 | Port keeps clear of starboard; windward of leeward; clear astern of clear ahead. | §4 rows 6 to 8. | matches | | **Keep**. |
| P2 | 13 | After passing head to wind, keep clear until close-hauled; if both, the one on the other's port side or astern. | §3.4, §4 rows 4 and 5 (close-hauled = polar VMG angle minus 5°). | matches | | **Keep**. |
| P3 | 14 (a) | Avoid contact where she reasonably can; a right-of-way or room boat need not act until it is clear the other is not keeping clear; 43.1(c) exonerates her for a contact without damage or injury. | §5.1: "damage" = closing speed of at least 1.5 m/s; right-of-way boat penalised only for a damaging contact she did nothing to avoid. | simplification | None. | **Keep**. |
| P4 | 14 (b), (c) | New: do not **cause** contact between two other boats, or between a boat and an object that should be avoided (for example the committee boat). | Only contacts within the pair are judged. | missing | Chain collisions at a crowded line or mark: the boat that pushed B into C goes free. | **Simplification** for now (cause is hard to judge automatically); list it in the rules help. |
| P5 | 44.1(b) | A boat that causes injury or serious damage, or gains a significant advantage despite her penalty, must retire. | Any contact is a turn penalty; no damage model. | missing | Ramming costs one turn. DSQ limits (§9.5) catch repeat offenders. | **Simplification**: keep; optionally a "hard contact = DSQ" setting for ranked lobbies. |
| P6 | 15 | A boat that acquires right of way first gives room to keep clear, unless she got it through the other boat's action. | §5.2 with cause detection. | matches | | **Keep**. |
| P7 | 16.1, 16.2 | Right-of-way boat changing course gives room to keep clear; on a beat, starboard must not bear away onto a port boat that is passing to leeward of her if that forces port to change course at once. | §5.3; 16.2 tested as "passing astern" with bearing away. | matches (wording) | None: on a beat, passing to leeward of a starboard boat is passing astern. | **Follow** the wording in §5.3. |
| P8 | 17 | A boat that gets a leeward overlap from clear astern within two of her lengths must not sail above her proper course while it lasts, unless she promptly goes astern. **No exception any more for an overlap that starts while the windward boat is tacking.** | §5.4 and `rules.cpp` keep the exception (`W not tacking`). | outdated (2021) | The slam dunk: a port boat ducking a starboard boat that tacks on top of her is now bound by 17 once she overlaps. Changes a common upwind attack. | **Follow**: drop the condition (one line). |
| P9 | 18.1(a)(1) | Not between opposite-tack boats on a beat to windward. | §7.2, both beating within θ_CH + 10° of the mark bearing. | matches | | **Keep**. |
| P10 | 18.1(a)(2) | Not between opposite-tack boats when, at the mark, one of them must tack to sail her proper course and the other need not. | Missing. | missing | Windward marks approached on opposite tacks from the layline side (for example a starboard-hand mark, or a port boat that rounds without tacking while the starboard boat must tack). Low to medium. | **Follow** (compare each boat's tack for the next leg), or keep as a simplification. |
| P11 | 18.1(a)(3), (b) | Not between a boat approaching and one leaving; rule 18 stops once mark-room has been given. | §7.2; status ends when the entitled boat leaves the zone or completes her rounding with no hull within Z. | simplification | None noticeable. | **Keep**. |
| P12 | 18.2(a)(2) | Not overlapped when the first of them reaches the zone: **the boat that has not reached the zone** owes mark-room. | §7.3.1 and `rules.cpp`: the boat clear ahead is entitled (2021 rule). | outdated (2021) | Differs when the boat clear astern reaches the zone first: converging angles at a gate or leeward mark, and opposite-tack boats where rule 18 applies. Medium at gates. | **Follow**: freeze the status on who entered first (zone entry ticks are already kept). |
| P13 | 18.2(d) | The "unable to give mark-room from the start of the overlap" exemption is only for an inside overlap obtained from clear astern or by tacking to windward. | §7.3.3 applies it to any new overlap without a status. | different | Small. | **Follow** (add the two conditions). |
| P14 | 18.2(b), (c), (e) | Duty ends when the entitled boat passes head to wind or leaves the zone; with no 18.2(a) duty an overlapped outside boat gives the inside boat mark-room; in reasonable doubt the overlap was not made or broken in time. | §7.3 (doubt window 0.25 s). | matches / simplification | | **Keep**. |
| P15 | 18.3 | **Only at a mark to be left to port.** A boat that tacks from port to starboard in the zone has no 18.2 entitlement towards a starboard boat that is **fetching** the mark; if that boat has been on starboard since entering the zone, the tacker must not force her above close-hauled and must give mark-room if she gets inside. | §7.5 and `rules.cpp`: any rounding side; requires the **tacker** to be fetching; deletes the 18.2 status only towards boats on starboard since zone entry. | outdated (2021) and different (side) | Windward-mark layline tacks: who is protected changes in common port-tack approaches. Medium. Starboard-hand marks: Windmark applies a duty that does not exist. | **Follow**. |
| P16 | 18.4 | An inside overlapped right-of-way boat that must gybe sails no farther from the mark than needed until she gybes; **not at a gate mark**. | §7.7 and `rules.cpp`: no gate exception. | missing | Leeward gates are the default course; a boat holding a gate buoy wide can be penalised wrongly. Low to medium. | **Follow** (one condition). |
| P17 | 19.1, 19.2(b) | Rule 19 applies at an obstruction except where rule 18 applies and the obstruction is the mark or a boat overlapped with both; the outside boat gives the inside boat room unless unable from the start of the overlap. | §7.8: same tack, overlapped, both predicted within 1 L of it within 6 s. | simplification | | **Keep**. |
| P18 | 19.2(a) | New sentence: a right-of-way boat that changes course to choose her side must give room to keep clear (not exonerable). | Not judged separately; 16.1 catches most cases. | missing | Low. | **Simplification**: keep. |
| P19 | Section C preamble | Section C off at a starting mark surrounded by water from the approach to start until it is left astern. | §7.8, §7.10: 18 never at line ends, 19 off while approaching to start until passed. | matches (wording) | | **Follow** the wording. |
| P20 | 18 at finishing marks | Finishing marks are marks with zones; rule 18 applies at them like any other mark. | §7.10: treated as obstructions; rule 18 off. | simplification | Close finishes at the committee boat: barging for the finish has no mark-room answer. Medium in tight finishes. | Owner: **keep** for the demo, **follow** before 1.0 (the rule 18 machinery already exists). |
| P21 | 20 | Hail "Room to tack" near an obstruction while close-hauled or above, not at a mark a fetching boat would have to alter for; the hailed boat tacks or answers "You tack" and gives room; 18.2 off between them until done. | §7.9, optional and off by default; action already called "room to tack". 18.2 switch-off not written. | simplification | | **Keep** as Phase 2; add the 18.2 switch-off when built. |
| P22 | 21.1, 21.2 | Boat returning to start (or to comply with the I flag) keeps clear until completely on the pre-start side; a boat taking a penalty keeps clear; Section A off while 21 applies. | §4 rows 2 and 3 (as "22.1", "22.2"). | matches (numbers outdated, D2) | | **Keep** behaviour, rename codes. |
| P23 | 21.3 | A boat moving astern or sideways to windward by backing a sail keeps clear. | Not judged. | missing | None unless the physics lets boats back sails. | **Keep** out (not applicable). |
| P24 | 22 | Avoid a capsized, anchored or aground boat or one helping someone in danger. | Not applicable. | n/a | | **Keep** out. |
| P25 | 23.1 | A boat not racing must not interfere with racing boats. | Ghosts cannot interact (§6.3): stricter than the rule. | matches | | **Keep**. |
| P26 | 23.2 | Do not interfere with a boat taking a penalty, on another leg, or returning under 21.1, unless (after the start) you are sailing your proper course. | Not judged. | missing | Online griefing: parking on a boat doing her turns, lapped boats fouling leaders. Low to medium. | **Simplification** for now; revisit with anti-griefing work. |

### 2.3 Part 3 and starting

| # | Rule | Current rules (our words) | Windmark now | Kind | Gameplay impact | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | 26 | Warning 5 min (or as the NoR or SIs say), preparatory 4 min with P, I, Z, Z with I, U or black, one minute, start. | `5-4-1-0`, plus `3-2-1-0` for quick online races. | simplification | | **Keep** (3-2-1-0 is a sailing-instruction style variant; say so in `race.md`). |
| S2 | 26 flags | "Z with I" is a valid preparatory signal. | Flags `P`, `I`, `Z`, `U`, `black`; no Z with I. | missing | Low. | **Keep**, or add later (it combines two checks that exist). |
| S3 | 28 | Sail the course (string test, gates from the previous mark's direction), correct errors before finishing. | `race.md` §5 winding and gate tests. | matches | | **Keep**. |
| S4 | 29.1 | Flag X when a boat is over at her signal or must comply with 30.1; down when all have returned, at most 4 min. | `race.md` §4.3. | matches | | **Keep**. |
| S5 | 29.2 | General recall when the committee cannot identify the boats over, or after an error. | Optional, on a count threshold; the server always identifies every boat. | simplification | | **Keep** (game choice, off by default). |
| S6 | 30.1 | I flag: on the course side of the line or its extensions in the last minute: return around an end. | `race.md` §4.3. | matches | | **Keep**. |
| S7 | 30.2, 44.3(c) | Z flag: 20 % of the Did Not Finish score, rounded to the nearest tenth, never worse than DNF; it **stands if the race is restarted or resailed**, and a second identification in a later attempt adds another 20 %. | 20 % of the number of entries, rounded to a whole number, minimum 1 (`race.cpp`); a general recall **clears** the Z identification (`race.cpp` recall reset). | outdated and different | Scoring only, and series ties. The recall case removes the deterrent of Z after a recall. | **Follow** (small). |
| S8 | 30.3, 30.4 | U: disqualified unless the race is restarted or resailed. Black: disqualified even then, and may not sail the restart. | `race.md` §3.3, §4.5. | matches | | **Keep**. |
| S9 | 31 | Do not touch a starting mark before starting, a mark of the current leg, or a finishing mark after finishing. | `rules.md` §8 (one-turn penalty). | matches | | **Keep**. |
| S10 | 44.1(a) | Part 2 breach and rule 31 in the same incident: only the Part 2 penalty is owed. | No such rule; the 3 s penalty spacing (§9.1) drops whichever comes second, so a mark touch first can replace a two-turn Part 2 penalty by a one-turn one. | different | Low in one-turn mode; a loophole in two-turn mode. | **Follow** (keep the Part 2 penalty, drop the 31 one, when both are within the spacing). |
| S11 | 35 | If no boat sails the course within the time limit, the race is abandoned. | Every boat scores DNF (`race.md` §7.1). | different | Rating and series effect of a dead race. | Owner: **follow** (abandon: no results, no rating change) or keep. |

### 2.4 Part 4: other requirements and penalties

| # | Rule | Current rules (our words) | Windmark now | Kind | Gameplay impact | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | 41 | No outside help, except freely available information and a few safety cases. | Not judged; the HUD gives every boat the same information. | n/a | Online: voice coaching or spectators cannot be policed. | **Keep** out; a lobby fair-play rule if needed. |
| R2 | 42, Appendix P | Only wind and water propel the boat: no pumping, rocking, ooching, sculling, or repeated tacks or gybes without reason; Appendix P gives umpires on-water penalties for it. | Not judged. | n/a | Only if the physics rewards helm pumping, sheet pumping or roll tacks. | **Keep** out of the rules; the physics must give no gain from these (a check for the boat model, not for the rules engine). |
| R3 | 44.1 default | Two-Turns Penalty for Part 2, One-Turn for rule 31, unless the NoR or SIs specify another penalty. | Default `one_turn` for everything; `two_turns` available (`race.md` §2). | simplification | Shorter penalty, faster races. Matches umpired fleet racing practice (Appendix UF chooses a One-Turn Penalty, see R8). | **Keep** one turn as default (owner's earlier view), say in `rules.md` that the lobby setting stands in for the sailing instructions. |
| R4 | 44.2 turn shape | Each turn includes one tack and one gybe, all in the same direction; no number of degrees is required (Case 108). | 350° with at least one tack and one gybe (§9.3). | simplification | Slightly longer than the minimum (a turn from close-hauled through a tack and a gybe can be about 225°). Intuitive "360". | **Keep**. |
| R5 | 44.2 promptly | Turns must be made promptly; an interruption only as long as needed to keep clear under 21.2 is still prompt (Case 149). | A pause in turning over 3 s, or a reversal over 20°, resets the turn. | different | A boat that must stop turning to keep clear of a boat that sails into her can lose her whole turn. Low to medium in crowded fleets. | **Follow**: do not reset while she is the give-way boat under 21.2 in `Warning` or `Breach`. |
| R6 | 44.2 timing and place | First get well away from other boats, as early after the incident as she can, then turn without delay; at or near the finishing line, be completely on the course side before finishing. No ban on turning in a zone; a rounding may even be part of the turn (Case 108). | Fixed 45 s deadline, no turn counts inside the zone of the next mark or the last one rounded, a rounding resets the turn, late = extra penalty. | simplification | See §3 (WM-056): the cause of most late-penalty DSQs. | See §3. |
| R7 | 44.3 | Scoring Penalty only if the NoR or SIs say so (yellow flag, points). | Not offered except the Z flag. | n/a | | **Keep** out. |
| R8 | Appendix UF (umpired fleet racing, a World Sailing development rule, version Feb 2025) | The format closest to an automatic umpire: penalties are One-Turn (the option events pick); a boat need take a penalty only when signalled; a boat taking or setting up a penalty has no proper course; umpires assume nothing changed until certain ("last point of certainty"); a boat that fails to take a signalled penalty, or takes it wrongly, gets a new penalty **and the original is cancelled**; an optional narrower mark-room (no farther than her proper course). | One-turn default, automatic signalling, doubt window: all in line. A late penalty is **added** to the one still owed (§9.4). | different | The stacking makes a boat owe 2, then 3 penalties and be DSQ'd (§9.5) quickly. | Owner: consider the UF model for late penalties (replace, not add; see §3 option E). |
| R9 | Disqualification limits | No count rule in the RRS; umpires may black-flag. | DSQ at 3 pending or 6 received (§9.5). | simplification | | **Keep**. |
| R10 | Part 5 | Protests, hearings, redress, appeals. | Automatic umpire; optional protest prompt (§10); no hearings. | simplification | | **Keep**. |

### 2.5 Match racing (Appendix C, Windmark §9.6)

The match mode is secondary; listed so the owner can decide whether "Appendix C, simplified" still holds.

| # | Rule | Appendix C (our words) | Windmark now | Kind | Recommendation |
| --- | --- | --- | --- | --- | --- |
| M1 | C7.2 penalty form | Not a turn: upwind leg, gybe then luff to close-hauled; downwind leg, tack then bear away past 90°. | Full 360 turns. | simplification | **Keep** for now; follow if match racing becomes a main mode (it changes the tactics a lot). |
| M2 | C7.3 timing | One penalty: any time after starting, before finishing. Two: one of them without delay once she reasonably can. Red flag: likewise without delay. No part of a penalty inside the zone of a rounding mark of the current leg. | One: no deadline; two: 15 s deadline; zone ban as in fleet; no red flag. | simplification | **Keep**. |
| M3 | C2.4 zone | Two hull lengths. | Course `zone_lengths` (3). | different | **Follow**: 2 L in match races. |
| M4 | C2.6, C2.7, C2.9 | Rule 13 also covers a gybe; 16.2 rewritten for boats sailing to a windward mark; rule 18 replaced by a shorter version (18.2 re-applied after leaving the zone; gybe/tack no faster than needed). | Fleet 13, 16.2, 18 (rule 17 dropped, as in C2.8). | different | **Keep** as documented simplification, list in §9.6. |
| M5 | C4, C7.2(e) | Entry: outside the line at right angles through her assigned end at the preparatory signal, cross the line course side to pre-start side within 2 min; offsetting penalties cancel (except red-flag ones). | `race.md` §3.4, §9.6. | matches | **Keep**. |

### 2.6 New in 2025-2028 but not relevant to Windmark

Rule 50 crew harnesses, 56.3 tracking devices, 40 personal flotation devices, the Part 5 renumbering (60 to 65),
60.2(b) protest hails, 63.7 reopening, 65 liability, 78, 89.2, Appendix R fees, abandonment flag N wording.

## 3. Penalty deadline (WM-056)

### 3.1 What the rules require

- **When**: rule 44.2 asks the boat first to get **well away from the other boats, as early after the incident as
  she can**, and then to make her turns **without delay**. There is no number of seconds. "Well clear" is not defined; the
  test is that she is out of the way of boats that could interfere. Case 149: once well clear, an interruption only
  as long as needed to keep clear (21.2) still counts as prompt. A boat that delays has not taken the penalty and
  can be protested (and in practice disqualified).
- **Where**: in fleet racing there is **no location rule**. A boat may take her turns in a zone, and Case 108 even
  accepts a rounding as part of the turn (for a mark touch), provided she is clear of other boats, turns promptly
  and gains no advantage (otherwise 44.1(b): retire). While turning she keeps clear of everyone (21.2), and others
  should not interfere with her unless sailing their proper course (23.2).
- **Before finishing**: near the line she must be completely on the course side before she finishes.
- **The zone ban exists only in match racing**: Appendix C (C7.3(b)) forbids any part of a penalty inside the zone of a
  rounding mark of the current leg, and asks for a penalty without delay only for a second outstanding one or a
  red-flag penalty.
- **Umpired fleet racing** (Appendix UF): the umpires signal the penalty; a boat that does not take it, or takes it
  wrongly, is penalised again and the original is cancelled; serious cases are disqualified by black flag.

So Windmark's 45 s deadline and its ban on turns in the zones of the next and the last mark are both Windmark
simplifications: the deadline makes "as soon as possible" enforceable, the ban (the match-racing rule applied to fleets) stops a
mark rounding from counting as half a turn. The problem in WM-056 is their combination: the clock runs while the
ban forbids the turn.

### 3.2 Why it bites on the default course

- Zone radius 3 L: about 22 m for wm7, 36 m for wm12. With the offset mark 60 m from the windward mark the two
  zones nearly touch (wm7) or overlap (wm12), and the boat is inside the zone of "the mark she is heading for" or
  "the one she last rounded" from the windward-mark approach until well down the run. The same happens at a gate
  (both buoys count).
- From WM-058: about 10 % of AI boats are disqualified, mostly by `44.1-late`; clearing the zones near the
  windward/offset pair or the gate takes a wm7 30 to 60 s, so the 45 s runs out, a late penalty is added, the
  boat now owes two, and a third one disqualifies her (§9.5).
- Humans hit the same trap: a foul in the windward-mark approach is a likely DSQ unless the player knows to wait
  and turn fast.

### 3.3 Options

| Option | Change | Pros | Cons |
| --- | --- | --- | --- |
| A. Clock only runs while a turn could count | The 45 s counts only ticks where the boat is outside the banned zones and has not just rounded (and, for a pre-start penalty, the time she may turn). HUD shows the countdown paused with "clear the zone". | Fixes WM-056 directly; keeps the anti-exploit ban; same rule for humans and AI; easy to explain. | A boat could sail a long leg mostly inside zones (short courses) and delay; needs a cap (see A+). |
| A+. A with a cap | As A, plus an absolute limit (for example 120 s after the penalty, or "before rounding the mark after next"). | Bounded delay. | One more number to explain. |
| B. Longer fixed deadline | `T_serve` 90 s, nothing else. | One number. | Still fails on short legs and at the windward/offset pair for slow boats; a long deadline also invites waiting for a good moment. |
| C. Follow the RRS: no zone ban | Turns count anywhere; a rounding cannot be part of the 350° (keep the reset on rounding) or can (Case 108). | Closest to fleet rules; no trap. | Turns in the zone in a crowd: 21.2 keep-clear fouls, mark congestion; if a rounding counts, about half a penalty is saved at every mark. |
| D. Narrow ban | Ban only inside the zone of the mark she is heading for (not the one she has rounded), or only while another racing boat is within a few lengths. | Lets the boat turn right after rounding, which is what sailors do. | The "rounded mark" ban was what stopped turning straight out of a rounding with the rounding's heading change; needs the reset on rounding kept. |
| E. Late penalty replaces | With any timing option: missing the deadline converts the owed penalty into a new one (count stays) with a fresh deadline, as in Appendix UF; a second miss disqualifies, or adds as today. | Stops the 1 then 2 then 3 pending cascade to DSQ; matches umpired practice. | Weaker deterrent if the deadline is generous; pick the second-miss rule. |

### 3.4 Recommendation (for the owner to decide)

**A+ with E**: the 45 s counts only while a turn could count (outside the banned zones, not on a rounding tick),
with an absolute cap of about 120 s after the penalty; a missed deadline replaces the owed penalty instead of
adding to it, and a second miss in the same race disqualifies. Keep the zone ban and the reset on rounding as a
documented simplification borrowed from match racing, and say in the rules help that the real fleet rules allow
turns anywhere once well clear. Also take R5 (do not reset a turn that pauses to keep clear). This leaves the
spirit of "as soon as possible" intact, removes the trap at the windward/offset pair and gates, needs no course
changes (the offset distance stays a course-design question, not a rules one), and is the same for humans and AI.

If the owner prefers the smallest change: **A alone**, which is what WM-056 proposed.

## 4. Owner decisions (2026-10-05, WM-095) and status

Follow the Racing Rules of Sailing 2025-2028 in everything, with exactly two documented exceptions: every penalty is
one 360° turn (fleet and match), and a penalty must be completed within 120 s of the incident, the clock never
paused. All items below are **done** on branch `rules2025` (WM-095), each with a unit test.

1. Penalty deadline and zone rule (§3, R3, R6, R8): **done**. Fleet races: no zone ban, a turn counts anywhere (a
   rounding may be part of it); a penalty not completed within 120 s of the incident disqualifies (no stacking).
   Match races: Appendix C timing (one penalty may wait until finishing; with two, one within 120 s), no part of a
   penalty in the zone of a rounding mark of the leg, 2-length zone (M2, M3). One 360° turn everywhere (M1 form not
   used). `rules.md` §9.2 to §9.6.
2. Rule codes and citations in the 2025-2028 numbering (D1, D2): **done**. Codes `21.1`, `21.2`, `44.2-late`;
   exoneration cited as 43.1, interfering as 23 (`rules.md` §4, §6, §11; `hud.md` §12.3).
3. Rule 17 without the tacking exception (P8): **done** (`rules.md` §5.4).
4. No proper course before the starting signal (D7): **done**; rules 17 and 18.4 cannot be broken before it
   (`rules.md` §3.7).
5. 18.2(a)(2) first boat to reach the zone (P12) and 18.2(d) conditions (P13): **done** (`rules.md` §7.3).
6. 18.3 only at port-hand marks, the starboard boat fetching (P15): **done** (`rules.md` §7.5).
7. 18.4 not at gate marks (P16): **done**, and not at finishing marks (`rules.md` §7.7).
8. 18.1(a)(2) (P10): **done**, judged from each boat's turn to the course after the mark (`rules.md` §7.2).
9. Rule 18 at finishing marks (P20): **done** (`rules.md` §7.10).
10. Zone measured from the mark outline (D5) and 2 L in match races (M3): **done** (`rules.md` §7.1; HUD zone circle,
    `hud.md` §7).
11. Z flag: 20 % of the DNF score to the nearest tenth, standing after a general recall (S7): **done** (`race.md`
    §3.3, §4.5, §9). Rule 29.1 now also applies under Z (a boat over at the gun returns), which a recall under Z
    needs.
12. Rule 31 with a Part 2 breach in the same incident (S10): **done**, the Part 2 penalty replaces the rule-31 one
    (`rules.md` §8).
13. A turn that pauses only to keep clear under 21.2 is not reset (R5): **done** (`rules.md` §9.3).
14. Time limit with no finisher abandons the race (S11): **done** (`race.md` §7.1).
15. Overlap measured with hull and equipment in normal position, the bowsprit (D3): **done** in the core and the VPP
    (`collision.sprit`); it takes effect for the shipped classes once `data/perf` is regenerated. The other
    simplifications of the old item 15 (14(b)(c), 44.1(b), 19.2(a) and continuing obstructions, 23.2, Z with I,
    Appendix C's rule changes) are listed as not judged in `rules.md` §15; open for the owner.

## 5. Sources

- World Sailing, Racing Rules of Sailing (current edition 2025-2028): https://www.sailing.org/racingrules/
- World Sailing, 2025-2028 RRS Changes and Corrections (Version 2, effective 1 Jan 2025 and 20 Apr 2026):
  https://www.sailing.org/document/changes-and-corrections/ ,
  https://www.sailing.org/wp-content/uploads/2024/12/Changes-and-Corrections-Version-2.pdf
- World Sailing, 2025-2028 RRS with Changes and Corrections (consolidated, April 2026):
  https://www.sailing.org/document/2025-2028-rrs-with-changes-and-corrections/ ,
  https://www.sailing.org/wp-content/uploads/2026/04/2025-2028-RRS-with-Changes-and-Corrections.pdf
- World Sailing, The Racing Rules of Sailing 2025-2028 (book as published June 2024, hosted by Asian Sailing
  Federation): https://www.asiansailing.org/wp-content/uploads/2024/07/RRS-2025-2028-Final.pdf
- World Sailing, Case Book 2025-2028 (version 2025-07), Cases 108 and 149:
  https://media.sailing.org/sailing/wp-content/uploads/2025/07/31104846/WS-Case-Book-2025-2028-v2025-07.pdf
- World Sailing Development Rule DR21-04, Appendix UF Umpired Fleet Racing (version February 2025, as published
  for an event): https://www.openskiff.org/wp-content/uploads/2025/04/DR21-04-Appendix-UF-Open-Skiff-v2025-clean_.pdf
- Dave Perry, A Quick Overview of the Significant Rule and Game Changes in the 2025-2028 RRS (US Sailing, 1 Jan
  2025): https://www.ussailing.org/wp-content/uploads/2025/01/A-Quick-Overview-of-the-Significant-Rule-and-Game-Changes-January-1-2025-by-Dave-Perry.pdf
- US Sailing, Changes to RRS 2025-2028 that affect race administration:
  https://www.ussailing.org/wp-content/uploads/2025/01/Changes-to-RRS-2025-2028-that-affect-Race-Admin.pdf
- RYA, Changes to the racing rules:
  https://www.rya.org.uk/network/running-racing/guidance-and-good-practice/racing-rules/changes-to-the-racing-rules/
- Fernhurst Books, Changes to the RRS 2025-2028 (the November 2024 amendments):
  https://fernhurstbooks.com/_userfiles/pages/files/rule_changes.pdf
- For the 2021-2024 comparison: World Sailing RRS 2021-2024, rules 1 to 56:
  https://sopyc.com.au/documents/20124/50892/1.+2021-2024-RRS-1-to-56.pdf ; SailZing on the 2021 Section D
  renumbering and rule 43: https://sailzing.com/racing-rules-of-sailing-2021-2024-rules-21-23/
