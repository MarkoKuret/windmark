---
id: WM-195
title: 'Helm: boat tracks straight by default (weather helm off), realism option'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 17:44'
updated_date: '2026-11-07 18:08'
labels: []
dependencies: []
priority: high
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner wants the boat to go straight with the helm centred. Weather helm becomes an option (default off); spec first, then core, data loader and settings. AI and tests stay green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With the option off a boat at any trim holds its heading with the helm centred (test). Settings expose Weather helm on/off, default off; boat.md documents it.
<!-- AC:END -->
