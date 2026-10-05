---
id: WM-056
title: 'Decide: penalty deadline near the windward and offset marks'
status: Done
assignee: []
created_date: '2026-09-25 19:18'
updated_date: '2026-10-05 09:35'
labels:
  - decide-later
dependencies:
  - WM-016.14
priority: low
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-010: on the default course the offset mark is 60 m from the windward mark; a boat penalised at the windward mark is inside one zone or the other for most of the 45 s it has to serve (rules.md 9.4), so turns come late and extra late penalties follow. Longer deadline, or offset mark farther away (courses.md)? Owner question, set aside on 2026-09-25: answer once races with AI run in the game (after WM-016.14).

Update from WM-058 (2026-09-26): about 10 % of AI boats are disqualified, mostly 44.1-late: the 45 s serve deadline (rules.md 9.4) keeps running while 9.3 forbids the turn inside the zones of the next mark and the last mark rounded; clearing them near the windward/offset pair or the gate takes a wm7 30 to 60 s. Proposal: the deadline only runs while a turn could count (outside those zones). A rules change for human players too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decided; spec and data updated to match
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decisions (2026-10-05) on docs/design/rules_check.md: follow the Racing Rules of Sailing 2025-2028 in everything, with exactly two documented exceptions: (1) penalties are always a single 360 degree turn (fleet and match; no two-turns option as default, no Appendix C penalty form); (2) the penalty must be completed within 120 s of the incident (stand-in for 'as soon after the incident as possible'); the clock is not paused and there is no other timing rule in fleet racing. Fleet racing: no ban on penalty turns inside mark zones; a turn may be taken anywhere. A missed deadline disqualifies, as a protest would (coordinator's pick for the unstated case; owner may change to the umpired-fleet 'new penalty replaces' model). Match racing: Appendix C timing (one penalty may be held until finishing, with two one of them without delay, i.e. within the 120 s; no part of a penalty inside the zone of a mark being rounded, as Appendix C says; 2-length zone). All other items in rules_check.md 4 (rule numbers, rule 17 tacking exception removed, no proper course before the start, 18.2(a)(2), 18.2(d), 18.3 port-hand marks, 18.4 not at gates, 18.1(a)(2), rule 18 at finishing marks, zone from the mark outline, Z flag scoring and recall, rule 31 with a Part 2 breach, no reset of a turn that pauses to keep clear, time limit with no finisher, overlap measured with the sprit) follow the current rules. Implemented in WM-095.
<!-- SECTION:NOTES:END -->
