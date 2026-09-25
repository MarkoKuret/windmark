# Roadmap

*Plan of 2026-09-25. Development is AI-assisted and fast, so the pacing items are wishlists, playtests and the
fixed Steam calendar, not code. Dates are targets counted from 2026-09-25.*

## Overview

| Phase | Window | Gate to the next phase |
| --- | --- | --- |
| 1. Foundations | Weeks 1–2 | Repo, specs and tools in place |
| 2. Clean core and boat data | Weeks 1–3 | One class sails from generated tables, headless tests pass |
| 3. Online prototype | Weeks 2–4 | 8 boats race online with AI filling slots |
| 4. Front end and boats | Weeks 3–6 | A race looks good enough to clip |
| 5. First clips and Steam page | Weeks 3–5 onward | Clips posted, Discord open, Coming Soon page live |
| 6. Closed online beta | Months 2–4 | Stable scheduled races with outside players |
| 7. Public demo | Months 3–4 | Demo on Steam before the chosen Next Fest |
| 8. Early Access | Months 4–6 | Launch after Steam Next Fest (Feb 2027 if targets hold, else June 2027) |

## 1. Foundations (weeks 1–2)

- Repo layout: `core/`, `server/`, `game/`, `tools/`, `docs/`.
- Planning docs (this set) and behaviour specs in `docs/specs/`: boat model, wind and waves, racing rules, race
  flow, AI, networking.
- Boat-class file format (hull, rig, sails, appendages, crew).
- Build and headless test setup for the core and the server.

## 2. Clean core and boat data (weeks 1–3)

- **VPP tool** (`tools/vpp`): hull and rig parameters → speed, heel, trim and acceleration tables per sail.
- **Boat generator** (`tools/boatgen`): hull, deck, appendages, rig and sails from the class file; reusable deck
  hardware parts; generated UVs.
- **C++ core** on the 50 ms deterministic tick: table-driven boat dynamics, wind field and waves from a shared seed,
  course and marks, racing-rules engine with penalties, race flow (start sequence, finish, results), AI helms,
  collisions.
- Headless tests: polar check against the tables, turning and tacking, a full AI race that finishes, determinism
  (same seed and inputs → identical result).
- First original class: a sportsboat or a GP monohull.

## 3. Online prototype (weeks 2–4)

- Headless authoritative server on the core; one room, up to 16 boats.
- Client prediction with reconciliation for the own boat; 100–150 ms interpolation for others.
- UDP with a reliability layer; delta snapshots with distance-banded update rates.
- AI boats fill empty slots; players can join a race in progress at the next start.
- Server replay recording (the basis for protests and clip export).
- One cheap EU VPS; measured bandwidth and CPU per room.

## 4. Front end and boats (weeks 3–6)

- Godot front end on a thin layer over the core: water, sky and sail shaders; generated boats with liveries.
- HUD: speed, wind, laylines, rules hints, penalty display with the reason.
- Controls for keyboard, gamepad and Steam Deck; camera modes.
- Replay viewer with free camera and **clip export**; scripted camera paths for the trailer.
- Minimal menus: quick race vs AI, server browser, join, settings.

## 5. First clips and Steam page (from weeks 3–5)

- Short clips (crossings, starts, penalties, rules quizzes) to Reddit, Shorts, TikTok, sailing clubs and classic
  sailing game communities; Discord opens as the hub.
- Capsule and key art (~$50, image model); Steam app fee paid once clips show pull.
- Steam Coming Soon page with the first trailer (in-engine capture); Playtest signup enabled.
- First paid test (€50–200), measured by cost per Discord join or signup.

## 6. Closed online beta (months 2–4)

- Founders' Fleet (community club admins and racers) and 3–5 pilot clubs via Steam Playtest.
- Scheduled "race every 15 minutes" rooms; weekly community races.
- Match racing (pre-start, umpire calls); second original class.
- Onboarding: first race within 10 minutes; assists that are not catch-up (auto-trim, laylines, rules hints).
- Performance pass on Steam Deck and a low-end PC; second server region if players need it.
- Metrics: D7 retention >20%, median session >25 minutes, penalty disputes answered by replays.

## 7. Public demo (months 3–4)

- Demo build: 2 classes, 1 venue, quick race vs AI and online rooms.
- Machine-translated EN/FR/DE/IT/ES/SL.
- Load test at 500 concurrent players.
- Press kit; sailing-media and streamer outreach.

## 8. Early Access (months 4–6)

- Steam Next Fest with the demo, then Early Access at €14.99–19.99 with a small launch discount.
- Gate: ~5k+ wishlists by the fest, stable online, demo median playtime >30 minutes. If short, take the next fest.
- Launch regatta in the Discord; ranked ladder and rankings.
- After launch: monthly updates (classes, venues, team racing), America's Cup season push (Jul 2027), class packs
  about 6 months after EA, Club/Coach edition pilots, 1.0 about 9–12 months after EA.

## Open decisions

| # | Decision | Status (2026-09-25) |
| --- | --- | --- |
| 1 | Product name | Working name Windmark; final after the EU trademark search; Sailmark backup (`NAMING.md`) |
| 2 | Company and legal | Deferred: individual on Steam; s.p. or family company later; legal via lawyer friend |
| 3 | Trademark filing | Deferred until the name is final and there is traction |
| 4 | Premium or free-to-play | **Decided:** premium EA plus free demo |
| 5 | Price point | Open: €14.99 (more players) or €19.99 (more per sale) |
| 6 | Web version | Business decision later; maybe a free rules trainer |
| 7 | Engine | **Decided for now:** Godot; Unity if consoles or widest mobile become firm goals; Unreal ruled out |
| 8 | Early Access classes | Open: 2–3 original classes (e.g. sportsboat, GP monohull, foiling cat). Which ones? |
| 9 | Real class or event licences | Open; recommendation: after EA, starting with small class associations |
| 10 | Club/Coach edition | After EA traction; needs a company to invoice |
| 11 | Next Fest and EA date | Open: Feb 2027 fest (fast) or June 2027 (safer, EA just before the America's Cup) |
| 12 | Budget | **Decided:** lean, ~€100–300 until traction; scale ads only on positive tests |
| 13 | Community approach | Open: who contacts which club; Founders' Fleet gets badge, credits, free key |
| 14 | Help | Open: a volunteer community manager from the beta, when? |
| 15 | America's Cup 2027 push | Open: how much effort (generic foiling class, no event marks) |
