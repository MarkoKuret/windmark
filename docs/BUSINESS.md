# Business plan

*Draft of 2026-09-25. Market figures come from desk research and carry a source and date; estimates are marked as
such. Owner decisions of 2026-09-25 are folded in. Marketing is in `MARKETING.md`, the name in `NAMING.md`, the
schedule in `ROADMAP.md`.*

## Summary

- **The gap:** nobody sells a well-made, fast, rules-accurate online fleet and match racing game on PC. The market
  leader is a free-to-play browser/mobile game with pay-to-win complaints; the official America's Cup game lost its
  players within weeks; the Steam sailing sims are slow solo or cruising games.
- **The market is a niche:** sailing games sell tens of thousands of copies on PC, not millions. A good premium
  release can plausibly sell **5k–30k copies in year one (≈ €45k–270k net)**. Enough to pay a solo developer, not
  venture scale.
- **Positioning:** *"Real racing. Real rules. Short races."* Honest skill, a proper rules and penalty engine with
  replays that explain every call, AI boats filling every race, and a light client (low-end PCs, Steam Deck).
- **Model:** premium Steam Early Access at **€14.99–19.99** plus a free demo. No virtual currency, no pay-to-win.
  Later: boat-class packs, a Club/Coach edition, sponsored regattas.
- **Spend:** lean until traction. Realistic spend before traction is **€100–300** (`Budget` below).

## 1. Market

### 1.1 Sailing games today

| Title | Platform, model | What we know (source, date) |
| --- | --- | --- |
| Virtual Regatta Inshore / Offshore (2006–) | Browser, iOS, Android; free-to-play | 1M+ players claimed; World Sailing eSailing partner. Owned by 52 Entertainment since Sep 2021 ([NextStep](https://www.nextstep-magazine.com/deals/rachat-de-virtual-regatta-par-52-entertainment-group/)). See 1.2 |
| AC Sailing (Apr 2024–) | PC (Steam, Epic); free + cosmetics €8.79–26.49 | Official America's Cup game, team simulator physics, €25k E-Series prize. 207 reviews, 70%. **Peak 120 concurrent at launch, now ~1–4** ([Steam](https://store.steampowered.com/app/2706370/); [Steambase, 2026](https://steambase.io/games/ac-sailing/steam-charts)) |
| Sailaway III (Nov 2024–) | PC/Mac, €14 + in-game currency for boats | 159 reviews, 68% ([Steam, Sep 2026](https://store.steampowered.com/app/2631870/Sailaway_III/); [pricing](https://sailaway.world/pricingsa3)) |
| eSail Sailing Simulator (2019–) | PC/Mac, €33.99 | ~800 reviews, 92–93%; 10–19 average concurrent, peak 52 (Aug 2025) ([Steam](https://store.steampowered.com/app/794860/eSail_Sailing_Simulator/); [Steambase](https://steambase.io/games/esail-sailing-simulator/steam-charts)) |
| Sailwind (2022–, EA) | PC, premium | Cargo/exploration, not racing. ~2k reviews, 88–89%; **SteamSpy 50k–100k owners** ([SteamSpy](https://steamspy.com/app/1764530)) |
| Laylines (due Mar 2027) | PC (Steam) | Syndicate-management sim with real-time match race duels "under real racing rules" ([Steam](https://store.steampowered.com/app/5053220/Laylines/)). **Direct competitor to watch** |
| Sail Simulator 5 (~2012) | PC, ~$30 | Old, low profile ([Stentec](https://www.stentec.com/en/simulator/product-sail-simulator-5-en)) |
| SailX (dead) | Browser, iPhone | Tactical inshore racer with rules; shut down after a hack. People still ask for "a game like SailX" ([Sailing Anarchy](https://forums.sailinganarchy.com/threads/game-like-sailx.239805/)) |
| Coaching tools | Web, apps | Tactical Sailing, SailPro Sim, North U, Opti rules simulator: a small B2B coaching niche exists ([tacticalsailing.com](https://www.tacticalsailing.com/en/); [sailpro.app](https://www.sailpro.app/racing-simulator)) |

### 1.2 Virtual Regatta, the benchmark

- Vendée Globe players: 340k (2008–09), 1M+ (2020–21), **827k (2024–25)** ([Wikipedia](https://en.wikipedia.org/wiki/Virtual_Regatta)).
- Revenue €3.26M (2021), about €2.64M in the latest filed year, alternating profit and loss; 10–19 staff
  ([Pappers](https://www.pappers.fr/entreprise/virtual-regatta-442178786)). Even the leader earns about **€2–4 per
  player per year** (estimate).
- Freemium: paid options ~80% of Offshore revenue; Inshore credit packs $2.99–89.99, VIP $8.99
  ([App Store, Sep 2026](https://apps.apple.com/us/app/inshore-by-virtual-regatta/id1182301199)); sponsor packages
  ~€5k (2020, [Tip & Shaft](https://www.tipandshaft.com/esailing/virtual-regatta-2020/)).
- Owns official eSailing: World Sailing eSailing World Championship since 2018, $10k Grand Final pool
  ([World Sailing](https://www.sailing.org/esailing)).
- Store complaints: pay-to-win upgrades, lag and glitch tacks, penalty confusion, poor support, empty off-peak lobbies
  ([AppGrooves](https://appgrooves.com/app/virtual-regatta-inshore-by-virtual-regatta/negative)). **That is where
  Windmark competes.**

### 1.3 Who sails

These count sailors, not players, but show a worldwide, club-organised, reachable audience.

| Measure | Figure | Source |
| --- | --- | --- |
| US participants | 4.1M (2023) | [Sailing Virgins, citing SFIA/Statista](https://sailingvirgins.com/resources/sailing-industry-report) (secondary) |
| World Sailing | 144 member nations, ~120 class associations | [Wikipedia](https://en.wikipedia.org/wiki/World_Sailing) |
| Germany (DSV) | 1,223 clubs, ~180k members | [Statista DE](https://de.statista.com/statistik/daten/studie/1403100/umfrage/deutscher-segler-verband-anzahl-vereine/) |
| UK (RYA) | ~1,400–1,500 affiliated clubs | [RYA](https://www.rya.org.uk/club-centre-support/affiliates/faqs) |
| Australia | 360+ clubs | [Wikipedia](https://en.wikipedia.org/wiki/Australian_Sailing) |
| Optimist class | 150,000+ boats, 120+ countries | [Wikipedia](https://en.wikipedia.org/wiki/Optimist_(dinghy)) |

Estimate: 10,000+ racing clubs worldwide; 1% as Club/Coach customers would be ~100 clubs.

### 1.4 Calendar hooks

- **38th America's Cup, Naples:** Match 10–18 July 2027 ([Sail-World, Jan 2026](https://www.sail-world.com/news/293128/Americas-Cup-Match-dates-announced)).
- **SailGP:** ~215M season broadcast audience in 2025 ([Ministry of Sport](https://ministryofsport.com/sailgp-caps-fifth-season-with-record-230-million-economic-impact-and-audience-growth/)); short races and a younger audience suit short game races.
- Winter is the indoor-training season for clubs.

### 1.5 Comparable niches

| Comparable | Why | Figures |
| --- | --- | --- |
| Tape to Tape (hockey, 2023) | Niche sports game built on nostalgia | 53k wishlists pre-launch (27k from Next Fest), 34k units / $636k gross in 8 days ([How To Market A Game](https://howtomarketagame.com/2023/05/16/tape-to-tape-how-an-indie-sports-title-generated-amazing-sales/)) |
| Trackmania | Community and competition model | Free Starter + Club Access $19.99/yr ([PC Gamer](https://www.pcgamer.com/trackmania-changes-its-subs-model-after-belatedly-realising-it-was-too-generous-dev-says-it-has-to-be-realistic/)) |
| iRacing | Rules-policed online racing by subscription | $13/month or $110/year ([iRacing](https://support.iracing.com/support/solutions/articles/31000140123-how-much-does-it-cost-to-use-iracing)) |
| Steam baseline | Median indie lifetime sales | ~500–2,000 copies; Very Positive games with 100+ reviews typically $75k–300k ([Steam Page Analyzer](https://www.steampageanalyzer.com/blog/indie-game-sales-statistics), indicative) |

## 2. Audiences

| Segment | Size (rough) | Wants | Pays for | Reach |
| --- | --- | --- | --- | --- |
| **Players of classic sailing games and their online clubs** | Hundreds active, thousands lapsed (estimate) | Correct rules and penalties, match and team racing, liveries, club tools, own servers, rankings | Premium game, supporter packs, private servers | Their Discords and sites, Sailing Anarchy, direct beta invites |
| **Racing sailors, clubs, coaches** | Millions of sailors, ~10k racing clubs | Rules training, start and mark-room drills, winter training, protest replays | Clubs: €100–500/yr (estimate); individuals: the game | Federations, club newsletters, sailing media |
| **eSailing** | Thousands in qualifiers (not public) | Fair ranked racing, spectating | Mostly organisers/sponsors | Own leagues first; national associations later |
| **Sports and sim players on Steam** | Large | Learn in 10 minutes, skilful close crossings, good water, Steam Deck | €10–20 if reviews are Very Positive | Next Fest, tags, YouTube, streamers, Reddit |
| **Mobile players** | Very large, low ARPU | Free, short sessions | IAP/ads | Later, if at all |

The paying core is **PC players who sail or raced in classic sailing games**, plus **clubs and coaches**. Casual Steam
players are the upside.

## 3. Lessons from the competition

1. **Empty lobbies kill niche online games** (AC Sailing had a brand, real physics, prize money and a free price).
   Windmark needs AI boats filling every race, a server browser, scheduled "race every 15 minutes" rooms, low
   hardware demands and Steam login only.
2. **Pay-to-win is the leader's biggest weakness.** "No pay-to-win, ever" is a selling point.
3. **Correct rules get noticed.** Both leading games draw complaints about wrong penalties; replays that explain
   *why* a penalty was given are the differentiator.

## 4. Model and pricing

| Stream | When | How | Notes |
| --- | --- | --- | --- |
| **Premium Steam Early Access** | EA launch | €14.99–19.99; free demo | Core revenue. AI fleets offset the price wall on population |
| **Boat-class packs** | ~6 months after EA | €4.99–9.99 per pack | Anyone may race against pack boats; only helming one costs money, so lobbies don't split. Adds ~10–15% (estimate) |
| **Club/Coach edition** | After EA traction | Private rooms, rules-scenario editor, replay whiteboard, roster and results export; ~€150–500/yr per club, pilots free | Needs a company that can invoice |
| **Sponsored regattas** | Year 2 | Named online regattas, banners on marks and committee boats; €1–5k per event | Needs audience numbers first |
| Web version | Business decision | Maybe a free rules trainer / replay viewer as a funnel | Not the main product |
| Mobile, consoles | After Steam works | Port or companion app | |

Rejected for now: free-to-play (needs far more players and live ops), subscriptions (only work with a large
community), virtual currencies (EU consumer scrutiny, reputation).

### Unit economics (arithmetic)

Steam takes 30% (25% above $10M), $100 app fee recoupable after $1,000 revenue; Valve handles VAT
([1d3](https://www.1d3.com/blog/platform-fees)). A €17.99 price minus ~17% VAT, 30% Steam, refunds, regional
pricing and discounts gives **≈ €8–9 net per unit** in year one.

| Year-1 scenario | Units | Net (≈ €9/unit) |
| --- | --- | --- |
| Weak | 3,000 | ~€27k |
| Base | 12,000 | ~€108k |
| Good | 30,000 | ~€270k |
| Breakout | 60,000+ | ~€540k+ |

### Server cost (estimate from the architecture)

50 ms tick, server-authoritative, 8–16 boats per race: ~5–15 KB/s per player, 20–50 MB per player-hour. A cheap
EU VPS (Hetzner 2 vCPU/4 GB ≈ $4.6/month, [costgoat](https://costgoat.com/pricing/hetzner)) should run several
rooms; measure with a headless load test. A launch peak of 300 concurrent players fits on 1–3 boxes (€20–60/month).
Pay-per-use orchestration ([Edgegap](https://edgegap.com/resources/pricing)) only if numbers force it. Hosting is
not the constraint.

## 5. Company, legal, tax (lean)

| Item | Decision (2026-09-25) |
| --- | --- |
| Legal advice | ~€0: the owner's lawyer friend plus own research |
| Terms of service, privacy | Generic ToS and privacy policy that match the data actually collected (Steam ID, handle, stats, replays). Delete-my-data path |
| Trademark | Deferred until the name is final and there is traction (EUTM €850 first class, €50 second, [EUIPO](https://www.euipo.europa.eu/en/trade-marks/before-applying/fees-payments)) |
| Company | Deferred. Steam accepts individuals. Later a Slovenian s.p. or a family company. A foreign company does not avoid Slovenian tax |
| Tax | Steam and app stores are the reseller of record for VAT; direct sales (club licences, own shop) need VAT handling once they exist. Steam tax interview for US withholding |
| Age rating | IARC is free for participating stores; expect PEGI 3. Quick-chat only at first keeps moderation small |
| Anti-cheat | Server-authoritative sim; input validation, server replays, reports, Steam-bound ranked. No kernel anti-cheat |

## 6. Budget until traction

| Item | Spend | Approach |
| --- | --- | --- |
| Legal | ~€0 | Lawyer friend, generic ToS/privacy |
| Trademark, company | €0 (deferred) | After traction |
| Store fees | €0 now | Steam $100 app fee only when the social traction gate holds (`marketing/social_plan.md` §8) |
| Capsule and key art | €0–50 | In-engine render composed by the owner; no image-model art (Steam AI disclosure, reputation) |
| Trailer | €0 | In-house, scripted in-engine capture |
| Audio | €0 | Own |
| Servers | a few €/month | One cheap VPS until success |
| Paid ads tests | €50–200 | Measured by cost per Discord join or signup (`MARKETING.md`) |
| Events, merch | €0 | Only after revenue |
| **Realistic total before traction** | **€100–300** | |

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Empty lobbies | High | High | AI fills every race, scheduled rooms, server browser, solo content, regions |
| Too niche or hard for gamers | Medium | High | 10-minute onboarding, assists that are not catch-up (auto-trim, laylines, rules hints), casual vs ranked |
| Solo bandwidth (tech, art, marketing) | High | High | Tight scope (2–3 classes at EA), generated assets, community volunteers, marketing calendar |
| Marketing reach | High | High | Clip-first organic plan, small measured ad tests |
| Official eSailing locked to the leader | High | Medium | Own leagues and club tools; national associations and classes first |
| Laylines lands first (Mar 2027) | Medium | Medium | Different product (fleet racing, short races, AI fleets); keep distinct name and look |
| Name conflict found late | Medium | Medium | EU search before the Steam page; backup name ready (`NAMING.md`) |
| Web build rehosting | Medium | Low | Web only as a free trainer; online play server-side and account-bound |

## 8. Not verified

- Size of the classic sailing game club scene: no published counts; estimate a few hundred active racers.
- Virtual Regatta's latest revenue year label was ambiguous.
- US 4.1M sailors: secondary source.
- Hosting cost per player: estimate; measure.
