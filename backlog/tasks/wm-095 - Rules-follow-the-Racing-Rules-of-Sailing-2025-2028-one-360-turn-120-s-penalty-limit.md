---
id: WM-095
title: >-
  Rules: follow the Racing Rules of Sailing 2025-2028 (one 360 turn, 120 s
  penalty limit)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 09:35'
updated_date: '2026-10-05 10:56'
labels:
  - core
  - rules
dependencies: []
priority: high
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner decisions (2026-10-05) on docs/design/rules_check.md: follow the Racing Rules of Sailing 2025-2028 in everything, with exactly two documented exceptions: (1) penalties are always a single 360 degree turn (fleet and match; no two-turns option as default, no Appendix C penalty form); (2) the penalty must be completed within 120 s of the incident (stand-in for 'as soon after the incident as possible'); the clock is not paused and there is no other timing rule in fleet racing. Fleet racing: no ban on penalty turns inside mark zones; a turn may be taken anywhere. A missed deadline disqualifies, as a protest would (coordinator's pick for the unstated case; owner may change to the umpired-fleet 'new penalty replaces' model). Match racing: Appendix C timing (one penalty may be held until finishing, with two one of them without delay, i.e. within the 120 s; no part of a penalty inside the zone of a mark being rounded, as Appendix C says; 2-length zone). All other items in rules_check.md 4 (rule numbers, rule 17 tacking exception removed, no proper course before the start, 18.2(a)(2), 18.2(d), 18.3 port-hand marks, 18.4 not at gates, 18.1(a)(2), rule 18 at finishing marks, zone from the mark outline, Z flag scoring and recall, rule 31 with a Part 2 breach, no reset of a turn that pauses to keep clear, time limit with no finisher, overlap measured with the sprit) follow the current rules. Implement: rules.md, race.md, ai.md and hud.md first, then core/src/rules, race, AI penalty logic (ai.md 7.6 no longer avoids zones in fleet racing), HUD rule codes and penalty panel. Source: docs/design/rules_check.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 rules.md, race.md, ai.md and hud.md updated to the decisions; rules_check.md items marked done
- [x] #2 Core rules, race and AI implement them, each change with a unit test (rule codes renamed to 2025-2028 numbering)
- [x] #3 Quick, long and ai_long tests pass; ai.md 15 measurements recorded before and after (penalties, late penalties, DSQ)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner (2026-10-05): all three open points accepted as implemented: the rules.md 15 simplifications stay, rule 29.1 OCS under Z, a rounding may be part of a penalty turn (Case 108).
<!-- SECTION:NOTES:END -->
