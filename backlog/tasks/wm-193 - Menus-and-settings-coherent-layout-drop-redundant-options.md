---
id: WM-193
title: 'Menus and settings: coherent layout, drop redundant options'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 17:44'
updated_date: '2026-11-07 18:03'
labels: []
dependencies: []
priority: high
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
General UI polish across the main menu, setup, pause, results and settings. Several settings are redundant, do nothing, or duplicate each other; remove or merge them and make every remaining option take effect.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every setting left in the panel changes something observable in the game; redundant or dead ones removed. Menus share one layout rhythm (spacing, headings, hints, focus) across all panels.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit: docs/design/settings_audit_2026-11-07.md (every setting read somewhere; dropped the stick curve, sheet key rate, sheeting-turns-auto-trim-off, smooth switch; merged the four hold/toggle rows into Held keys and the four inversions into two). Rhythm: MenuTheme constants and helpers (MARGIN, LIST_GAP, SECTION_GAP, FOOTER_GAP, HELP_H, PAGE_MAX; list, gap, help_label, footer, subheading) used by every screen; footers: the way back left, the primary right; pause Quit to menu is Main menu; the pause settings page as wide as the main menu's. Previews: docs/design/menus_2026-11-07/ at 1280x800 and at 985x615 and 1600x1000 (the 130 % and 80 % UI-scale extremes). Spec: menus.md §1 to §5.
<!-- SECTION:NOTES:END -->
