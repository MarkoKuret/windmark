---
id: WM-087
title: 'Rules: check the latest World Sailing racing rules before release'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-04 10:54'
updated_date: '2026-10-05 09:35'
labels:
  - rules
dependencies: []
priority: low
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-04): before the public release (demo or Early Access), check rules.md and the game against the current Racing Rules of Sailing (World Sailing edition in force then), including the penalty: the game uses a one-turn penalty (rule 44.2 by default is a two-turns penalty); the owner judged switching to the 720 overkill for now. List every difference and decide each: follow the rule, or keep a documented simplification (rules.md 7.8 to 7.10).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 rules.md compared with the edition in force; differences listed
- [x] #2 Each difference decided by the owner (follow or documented simplification)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Comparison with RRS 2025-2028 (Changes and Corrections v2) in docs/design/rules_check.md: edition and changes (§1), every difference with kind, impact and a recommendation (§2), penalty deadline options for WM-056 (§3), and the list of owner decisions (§4). AC #2 waits for the owner.

Owner decisions (2026-10-05) on docs/design/rules_check.md: follow the Racing Rules of Sailing 2025-2028 in everything, with exactly two documented exceptions: (1) penalties are always a single 360 degree turn (fleet and match; no two-turns option as default, no Appendix C penalty form); (2) the penalty must be completed within 120 s of the incident (stand-in for 'as soon after the incident as possible'); the clock is not paused and there is no other timing rule in fleet racing. Fleet racing: no ban on penalty turns inside mark zones; a turn may be taken anywhere. A missed deadline disqualifies, as a protest would (coordinator's pick for the unstated case; owner may change to the umpired-fleet 'new penalty replaces' model). Match racing: Appendix C timing (one penalty may be held until finishing, with two one of them without delay, i.e. within the 120 s; no part of a penalty inside the zone of a mark being rounded, as Appendix C says; 2-length zone). All other items in rules_check.md 4 (rule numbers, rule 17 tacking exception removed, no proper course before the start, 18.2(a)(2), 18.2(d), 18.3 port-hand marks, 18.4 not at gates, 18.1(a)(2), rule 18 at finishing marks, zone from the mark outline, Z flag scoring and recall, rule 31 with a Part 2 breach, no reset of a turn that pauses to keep clear, time limit with no finisher, overlap measured with the sprit) follow the current rules.
<!-- SECTION:NOTES:END -->
