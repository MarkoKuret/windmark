# Roadmap

*Plan of 2026-09-25. No release date: each phase starts when the previous gate is met, and the game ships as soon as
it is ready. Development is AI-assisted and fast, so the pacing items are wishlists, playtests and the Steam calendar,
not code. Launch timing also watches the market: avoid launching into a huge release window (e.g. GTA VI).
Revised 2026-09-30 (proposed, for the owner): social media and the Discord start now as a marketing track alongside
phases 3 and 4, instead of after the online prototype (`marketing/social_plan.md`).*

## Overview

| Phase | Gate to the next phase |
| --- | --- |
| 1. Foundations | Repo, specs and tools in place |
| 2. Clean core and boat data | One class sails from generated tables, headless tests pass |
| Marketing track (from Oct 2026, alongside 3 and 4) | Social traction gate holds (below) |
| 3. Front end and boats | A race against AI looks good enough to clip |
| 4. Online prototype | 8 boats race online with AI filling slots |
| 5. Steam page and trailer | Coming Soon page live with an in-engine trailer; may open during phase 3 or 4 once the traction gate holds |
| 6. Closed online beta | Stable scheduled races with outside players |
| 7. Public demo | Demo on Steam before the chosen Next Fest |
| 8. Early Access | Launch after a Steam Next Fest once the gates hold |

## Marketing track (from October 2026)

Runs alongside phases 3 and 4; plan in `marketing/social_plan.md`, strategy in `MARKETING.md`.

- Accounts under the lock-in-free handle `playwindmark` (Instagram, YouTube, TikTok; the owner's own Reddit account).
- Discord open from the first week of posting, as the one link.
- Four vertical clips a week (Reels first, the same file to Shorts and TikTok) and one Reddit post: the weekly
  "Who's wrong?" rules quiz, close racing with the AI fleet, how the boats sail, built by a sailor.
- Capture from windowed runs the owner starts (OBS or Godot Movie Maker), plus the headless preview stills. Small
  capture tools in the backlog (label `marketing`): rules scenario loader, capture mode, portrait preset, clip cameras.
- Monthly review against the targets; stop or double down per format and platform.
- **Traction gate for the Steam page** (the owner's rule that the page waits for traction stays; the signal is now
  social, not the online prototype): two of 1,000 followers across platforms, 150 Discord members, one clip over
  50K views, weekly "where can I wishlist?" requests; plus capsule, a 30–60 s trailer and three distinct scenes.
  Reviewed monthly, aiming for a page before Steam Racing Fest (12–19 April 2027), which lists Coming Soon games.
- Name search closed by owner decision (2026-10-05, WM-030): no WINDMARK in the EU register; no legal gate.

## 1. Foundations

- Repo layout: `core/`, `server/`, `game/`, `tools/`, `docs/`.
- Planning docs (this set) and behaviour specs in `docs/specs/`: boat model, wind and waves, racing rules, race
  flow, AI, networking.
- Boat-class file format (hull, rig, sails, appendages, crew).
- Build and headless test setup for the core and the server.

## 2. Clean core and boat data

- **VPP tool** (`tools/vpp`): hull and rig parameters → speed, heel, trim and acceleration tables per sail.
- **Boat generator** (`tools/boatgen`): hull, deck, appendages, rig and sails from the class file; reusable deck
  hardware parts; generated UVs.
- **C++ core** on the 50 ms deterministic tick: table-driven boat dynamics, wind field and waves from a shared seed,
  course and marks, racing-rules engine with penalties, race flow (start sequence, finish, results), AI helms,
  collisions.
- Headless tests: polar check against the tables, turning and tacking, a full AI race that finishes, determinism
  (same seed and inputs → identical result).
- First original class: a sportsboat or a GP monohull.

## 3. Front end and boats

- Godot front end on a thin layer over the core: water, sky and sail shaders; generated boats with liveries.
- HUD: speed, wind, laylines, rules hints, penalty display with the reason.
- Controls for keyboard, gamepad and Steam Deck; camera modes.
- Replay viewer with free camera and **clip export** (offline races record seed and inputs locally); scripted camera
  paths for the trailer.
- Minimal menus: quick race vs AI, settings (server browser and join come with phase 4).

## 4. Online prototype

- Headless authoritative server on the core; one room, up to 16 boats.
- Client prediction with reconciliation for the own boat; 100–150 ms interpolation for others.
- UDP with a reliability layer; delta snapshots with distance-banded update rates.
- AI boats fill empty slots; players can join a race in progress at the next start.
- Server replay recording (the basis for protests and online clip export).
- One cheap EU VPS; measured bandwidth and CPU per room.

## 5. Steam page and trailer

Opens when the marketing track's traction gate holds, which may be during phase 3 or 4.

- Clips and the Discord are already running (marketing track); classic sailing game communities join with the
  Founders' Fleet once online races work.
- Capsule and key art from in-engine renders, edited by hand afterwards; the app icon is the one exception (image-model
  art, `docs/branding/`). Steam app fee ($100) paid at the gate.
- Steam Coming Soon page with the first trailer (in-engine capture); Playtest signup enabled.
- First paid test (€50–200), a boost of the best quiz clip, measured by cost per Discord join or wishlist.

## 6. Closed online beta

- Founders' Fleet (community club admins and racers) and 3–5 pilot clubs via Steam Playtest.
- Scheduled "race every 15 minutes" rooms; weekly community races.
- Match racing (pre-start, umpire calls); second original class.
- Onboarding: first race within 10 minutes; assists that are not catch-up (auto-trim, laylines, rules hints).
- Performance pass on Steam Deck and a low-end PC; second server region if players need it.
- Metrics: D7 retention >20%, median session >25 minutes, penalty disputes answered by replays.

## 7. Public demo

- Demo build: 2 classes, 1 venue, quick race vs AI and online rooms.
- Load test at 500 concurrent players.
- Press kit; sailing-media and streamer outreach.

## 8. Early Access

- Steam Next Fest with the demo, then Early Access at €14.99–19.99 with a small launch discount.
- Gate: ~5k+ wishlists by the fest, stable online, demo median playtime >30 minutes. If short, take the next fest.
- Launch regatta in the Discord; ranked ladder and rankings.
- After launch: monthly updates (classes, venues, team racing), a push around big sailing events (e.g. the America's Cup),
  class packs, Club/Coach edition pilots, then 1.0.

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
| 11 | Release timing | **Decided:** no fixed date; as soon as the gates hold, on the first suitable Next Fest, avoiding huge release windows (e.g. GTA VI) |
| 12 | Budget | **Decided:** lean, ~€100–300 until traction; scale ads only on positive tests |
| 13 | Community approach | Open: who contacts which club; Founders' Fleet gets badge, credits, free key |
| 14 | Help | Open: a volunteer community manager from the beta, when? |
| 15 | America's Cup push | Open: how much effort (generic foiling class, no event marks) |
| 16 | Front end or online first | **Decided:** front end first (phase 3), a playable race against AI, then networking (phase 4) |
| 17 | When marketing starts | **Proposed 2026-09-30:** social media and the Discord now, as a track alongside phases 3 and 4; the Steam page stays gated on traction, with a measurable social gate and Racing Fest (April 2027) as the target. Owner to confirm |
