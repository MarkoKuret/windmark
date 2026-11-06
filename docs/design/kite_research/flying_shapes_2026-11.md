# Kite flying shapes: published data for every Windmark spinnaker

Research date: 2026-11-03. Web research only, no code changes.

Quality tags used on every number:
- **[FS]** measured full-scale
- **[WT]** measured model / wind tunnel (or water tunnel)
- **[CFD]** CFD / FSI
- **[SM]** sailmaker guidance
- **[RULE]** class rule or rating certificate (planform only)
- **[EST]** estimate or my own derivation (method stated)

"Read" means I opened the full text or data file and took the number from it. "Abstract" means only the abstract or a quoted snippet was available.

---

## 1. Summary

| Kite | Analogue | Best flying-shape source | Quality | Reach / run covered | What is missing |
|---|---|---|---|---|---|
| wm7, 53.5 m² A on sprit | Melges 24 | Deparday et al. 2016, J/80 asymmetric, table 3 (already in hand) | [FS], photogrammetry, full 3D | AWA 64° and 124° (sail measured over about 60° to 145°) | Melges 24 kite is much "squarer" than the J/80 kite (leech/luff 0.96 vs 0.80), so the clew sits higher. Scale corner positions by planform, not by area. No Melges 24-specific shape data exists. |
| wm10, 100.5 m² A2 on sprit | Figaro 3 / Sun Fast 3300 / Class40 | J/80 [FS] scaled. Second choice: Stewart 34 A-kite (88.6 m², 10.4 m boat) full-scale VSPARS, Motta 2014/2015 | J/80 [FS] tables; SS34 [FS] figures only | J/80: 64°/124°. SS34: 70° to 120° runs, figures only | No tabulated SS34 sections (only plots). No Figaro/Class40 shape data. |
| wm12, 155.5 m² A2 on sprit | J/122 | J/80 [FS] scaled, cross-checked with the Carina (M&R 48, 175 m²) North Sails design shape: mid-span camber 31%, draft 50.9% at AWA 85° | [FS] + [CFD/design] | Carina: one AWA (85°), two trims | No measured J/122-size kite. SYRF FSI shapes (TP52, Swan 42, M&R 48, AWA 45° to 150°) exist but I could not obtain the report. |
| wm16, 268.5 m² A2 on sprit | TP52 | AC33 asymmetric spinnaker benchmark: flying shape measured by photogrammetry in a wind tunnel at AWA 55°, geometry published (Edinburgh DataShare). I sliced it: camber 27% low, 23% mid, 15% near head, draft 49 to 55%, twist 16° foot to head | [WT], geometry file, sections derived by me | Reach (AWA 55°) only | No grand-prix run shape. Borrow the J/80 124° trend for the run. |
| wm9, 44.5 m² symmetric on pole | Dragon / Etchells / Soling / J/24 | Moore / Lasher-Richards parametric IACC symmetric spinnaker series (5 sails, published equations, Peart 2022 thesis app. A). I evaluated the equations: camber 21% to 49% by sail and height, draft 50%, no twist | [WT] rigid models with a prescribed (parametric) shape, not a measured flying shape | Shape is fixed; tested over the whole AWA range by rotating the model | **No measured symmetric flying shape found in open literature.** No section twist or AWA dependence. Also: game area 44.5 m² is 25% to 50% bigger than any of the four analogue classes (29 to 36 m²). |
| wm21, 294 m² symmetric on pole | 12mR | Same Moore / Lasher-Richards IACC series (IACC is the 12mR's direct America's Cup successor; series full-scale at 1:25 is about 500 m²) | [WT] parametric | As above | No measured 12mR kite shape or dimensions. 12mR rule gives limits only. |

Bottom line:
- **Asymmetric reach:** two real measured data sets now exist in numbers: J/80 full-scale (in hand) and AC33 wind-tunnel geometry (new, sliced below).
- **Asymmetric run:** only the J/80 at 124° (plus the J/80 at 141° for corners).
- **Symmetric:** no open measured flying-shape tables exist that I could reach. The only numeric symmetric data is the Moore / Lasher-Richards IACC parametric series. Its shapes are the designed shapes of rigid wind-tunnel models, not photographs of a flying sail.

---

## 2. Data sets found (catalogue)

| # | Data set | Boat / sail | Kind | What it gives | Access |
|---|---|---|---|---|---|
| D1 | Deparday, Bot, Hauville, Augier, Rabaud (2016). *Full-scale flying shape measurement of offwind yacht sails with photogrammetry.* Ocean Eng. 127:135-143. https://doi.org/10.1016/j.oceaneng.2016.09.043 | J/80 asymmetric, tri-radial, about 68 m² | [FS] photogrammetry, AWA about 60° to 145° | Table 3: camber, draft, twist, entry angle at 6 heights, AWA 64° and 124°. Clew displacement. | Already with the caller. I could not reopen it: HAL (https://hal.science/hal-01379626) has bot protection, sam.ensam.eu returns 403, CORE is behind Cloudflare. |
| D2 | Motta (2015). *An experimental investigation of full-scale sail aerodynamics using pressures, shapes and forces.* PhD thesis, Univ. of Auckland. https://researchspace.auckland.ac.nz/handle/2292/27616 | J/80 (SJ80) and Stewart 34 (SS34) asymmetric spinnakers | [FS] VSPARS shape + pressures | Sail dimensions and stripe widths (table A.4). Shapes only as plots. Wind tunnel validation of clew position on a VO70 model. | Read |
| D3 | Motta, Flay, Richards, Le Pelley, Deparday, Bot (2014). *Experimental investigation of asymmetric spinnaker aerodynamics using pressure and sail shape measurements.* Ocean Eng. 90:104-118. https://doi.org/10.1016/j.oceaneng.2014.07.023 | SS34 and J/80 | [FS] | Same campaign as D2 | Abstract only (HAL blocked) |
| D4 | AC33 benchmark asymmetric spinnaker. Geometry: Edinburgh DataShare https://doi.org/10.7488/ds/2857 (resolves to https://datashare.ed.ac.uk/handle/10283/3676), file `Spinnaker_high_twist_16deg.igs`. Provenance: Arredondo-Galeana PhD thesis (2019) http://hdl.handle.net/1842/36074 and Viola and Flay (2011) Ocean Eng. 38:1733-1743 (accepted manuscript https://www.pure.ed.ac.uk/ws/files/12967578/Viola_Flay_2011OE.pdf) | AC33-class A-sail (designed for 510 m²), optimum AWA 55° | [WT]: flying shape measured photogrammetrically in a twisted-flow wind tunnel, then built as a rigid model | Full 3D surface. I sliced it into sections (section 6). | Read (IGES file downloaded and parsed) |
| D5 | Souppez and Viola (2024). *Water tunnel testing of downwind yacht sails.* Exp. Fluids 65:15. https://doi.org/10.1007/s00348-023-03752-2 (open: https://publications.aston.ac.uk/id/eprint/45950/1/s00348-023-03752-2.pdf) | Carina, McCurdy & Rhodes 48 (14.70 m LOA), spinnaker 175 m², North Sails design (Braun et al. 2016, SYRF) | [CFD/design] shape used as rigid model | Mid-span camber, draft, angle of attack at AWA 85° for two trims | Read |
| D6 | Moore (2004) ME thesis, *Numerical modelling of a series of parametric spinnakers*, Univ. of Auckland; Lasher and Richards (2007) J. Ship Res. 51(1):22-38 https://doi.org/10.5957/jsr.2007.51.1.22; equations and coefficients reprinted in Peart (2022) PhD thesis, appendix A, https://researchspace.auckland.ac.nz/handle/2292/64018 | Five rigid IACC-type symmetric spinnakers, 1/25 scale, 0.8 m² each | [WT] rigid parametric models (shape prescribed, forces measured) | Exact surface equations. I evaluated them (section 7). | Peart thesis read; Lasher and Richards abstract only |
| D7 | Augier, Paillard, Sacher, Leroux, Aubin (2021). *Numerical and experimental comparison of spinnaker aerodynamics close to curling.* J. Sailing Tech. 6(1):118-132. https://archimer.ifremer.fr/doc/00702/81388/85760.pdf | Asymmetric spinnaker model, twisted flow wind tunnel, AWA 100° | [WT] photogrammetry, 3 trims | Qualitative: clew moves forward and up when the sheet is eased. STEP geometries were on a Google Drive folder that now returns 404. | Read |
| D8 | Viola and Ponzini (2011). *A CFD investigation with high-resolution grids of downwind sail aerodynamics.* https://www.pure.ed.ac.uk/ws/files/69749812/Viola_marineCFD2011_aero.pdf | AC33 1:12.5 model, Politecnico di Milano wind tunnel | [WT] photogrammetry flying shape at AWA 45° | Geometry used for CFD; no section table | Read |
| D9 | SYRF *Downwind Aero Moments & Forces*, Phase 1, 2A, 2B, 2C (Braun, Richelsen, Schreber, North Design Services, 2016-2017), described at https://sailingscuttlebutt.com/?p=64858 | TP52, Club Swan 42, M&R 48 (Carina): two asymmetric designs each, plus a symmetric for the M&R 48; AWA 45° to 150°, TWS 8/12/16 kn | [CFD/FSI] | FSI flying shapes exist inside the study; the public deliverable is force/moment spreadsheets. Phase 2B varied the girth. | **Not obtained.** sailyachtresearch.org returned nothing usable. Worth asking SYRF directly. |
| D10 | Mausolf, Deparday, Graf, Renzsch, Böhm (2011). *Photogrammetry based flying shape investigation of downwind sails in the wind tunnel and at full scale on a sailing yacht.* CSYS 2011. https://doi.org/10.5957/csys-2011-003 | 38 ft cruiser-racer, symmetric and asymmetric spinnakers, wind tunnel and full scale | [FS] + [WT] | The only paper I found with a **symmetric** spinnaker photographed both in the tunnel and on the water | Abstract only (paywalled; ResearchGate blocked) |
| D11 | Graf and Müller (2009). *Photogrammetric investigation of the flying shape of spinnakers in a twisted flow wind tunnel.* CSYS 2009 | Spinnakers, Kiel twisted flow tunnel | [WT] | Design shape vs flying shape, effect of wind speed and twist | Abstract only |
| D12 | Richards, Johnson, Stanton (2001). *America's Cup downwind sails: vertical wings or horizontal parachutes?* J. Wind Eng. Ind. Aerodyn. 89:1565-1577. https://doi.org/10.1016/S0167-6105(01)00135-0 | IACC symmetric and asymmetric | [WT] | Title only (no abstract in OpenAlex) | Not read |
| D13 | Nava, Cater, Norris (2018). *Large eddy simulation of an asymmetric spinnaker.* Ocean Eng. 169:99-109. https://researchspace.auckland.ac.nz/handle/2292/44998 | 1/25 gennaker models in the Auckland tunnel | [CFD] | No section geometry tabulated | Read |

---

## 3. Planforms (all kites)

From class rules and certificates (collected by a sub-agent; checked arithmetic where noted).

**Area formulas**
- ORC symmetric: Area = SLU·(SFL + 4·SHW)/6.
- ORC asymmetric: Area = ((SLU+SLE)/2)·(SFL + 4·SHW)/6.
- IRC / TP52 rule / Figaro 3 class: SPA = ((SLU+SLE)/2)·((SFL + 4·SHW)/5)·0.83.
- Source: ORC Rating Systems 2024, rules 113-114, https://orc.org/uploads/files/Rules-Regulations/2024/ORC-Rating-Systems-2024.pdf [RULE].
- ORC classes an asymmetric with SHW/SFL < 0.85 also as a headsail set flying.

**Tack position:** ORC/IMS TPS is measured from the **front face of the mast** to the tack point (IMS 2022 F7.2, https://orc2.orc.org/rules/IMS%202022.pdf), not from the stem. Sprit beyond stem ≈ TPS − J − SFJ.

| Kite | Analogue sail | SLU | SLE | SHW | SFL | SHW/SFL | Area | Tack | Source [RULE] |
|---|---|---|---|---|---|---|---|---|---|
| wm7 | Melges 24 (class max) | 11.59 | 11.08 | 5.86 | 6.30 | 0.93 | 56.18 m² ORC | TPS 4.106 (sprit about 1.40 beyond stem); J 2.506, ISP 9.777 | ORC One-Design cert. 2019 https://data.orc.org/public/od/2019/melg24.od.pdf; class rules https://www.sailing.org/tools/documents/M24CR260321-[27184].pdf |
| (wm7 ref.) | J/80 test kite SJ80 | 12.00 | 9.55 | stripe width 7.72 at 1/2 height, 7.70 at 1/4, 5.86 at 3/4 | n/a | n/a | 63.1 m² | n/a | Motta 2015 thesis table A.4 [FS] |
| wm10 | Figaro 3 A2 | 16.02 | 13.74 | 9.08 | 9.19 | 0.99 | 112.86 m² ORC (class max 115 m²) | TPS 5.660 (sprit about 1.05); J 4.48 | ORC Club cert. SWE 24, https://matbrev.svensksegling.se/Files/ORCPdf//42daf4a7-791b-4582-b6f1-2da8d42a9487.html; class rule https://arbitrage.ffvoile.fr/media/xo5n2wat/figaro-3-fra-2021.pdf |
| wm10 | Sun Fast 3300 | 15.15 | 13.17 | 8.40 | 8.61 | 0.98 | about 99.2 m² IRC (my calc.) | n/a | IRC cert. "Ignition", snippet only https://ircrating.org/pdfdirectory/47739_IGNITION_RQ330.pdf |
| (wm10 ref.) | Stewart 34 test kite SS34 | 13.20 | 12.26 | stripe width 8.0 at 1/2, 8.63 at 1/4, 5.4 at 3/4, 2.9 at 7/8 | n/a | n/a | 88.6 m² | I 13.21, J 3.66 | Motta 2015 thesis tables 5.1, A.4 [FS] |
| wm12 | J/122 A2 | 19.46 | 16.23 | 10.12 | 10.20 | 0.99 | 150.73 m² ORC | TPS 6.430 (sprit about 1.53); J 4.609 | ORCi DH 2022 "Joule", https://matbrev.svensksegling.se/Files/ORCPdf//d8613550-c061-4e23-8884-7720666d0501.html |
| wm12 | J/122 A4 | 20.20 | 16.55 | 10.39 | 10.50 | 0.99 | 159.43 m² ORC | TPS 6.492 | ORCi 2018 "Joy Ride", https://www.vicmaui.org/pdfs/2018-documents/VM2018%20ORC%20Joy%20Ride%20ORCi%20Certificate%20rev%20June%202018.pdf |
| wm16 | TP52 | 25.51 | 21.70 | 13.78 | 13.70 | 1.01 | 269.67 m² IRC (rule max 270) | STL 8.70; rule max 9.00 from mast | IRC cert. "Red Bandit", snippet only https://ircrating.org/pdfdirectory/42459_RED%20BANDIT_GER8399.pdf; TP52 rule https://www.transpac52.org/wp-content/uploads/2022/12/2023-TP52-Rule.pdf |
| wm9 | J/24 | 8.13 | 8.13 | 5.22 | 5.20 | 1.00 | 35.34 m² | SPL 2.975 | ORC OD https://data.orc.org/public/od/2023/j24.od.html?nav=1 |
| wm9 | Soling (large) | 7.50 | 7.50 | 5.88 | 5.58 | 1.05 | 36.38 m² | SPL 2.695 | ORC OD https://data.orc.org/public/od/2023/soling.od.html?nav=1 |
| wm9 | Etchells (class) | leech 8.25-8.45 | n/a | no mid width defined; widths 5.91-6.31 at 5.485 m from head | foot 5.09-5.49 | n/a | n/a | pole ≤ 2.895 | https://etchells.org/assets/documents/IECA_CR_2026-01-01.pdf |
| wm9 | Dragon (class) | 6.90-7.00 | n/a | 4.88-5.08 at 3.5 m down luff | 4.60-4.80 | about 1.06 | about 29.3 m² (my calc.) | pole ≤ 2.240 | https://www.ussailing.org/wp-content/uploads/2020/07/DRA2020_CR_191021.pdf |
| wm21 | 12mR rule | ≤ 0.8·√(I²+J²) + 2.5 (about 18.6 with I 18.75, J 7.32) | = SLU | ≥ 0.75·foot (min only) | ≤ 2.5·J (about 18.3) | ≥ 0.75 | about 227 to 284 m² from the rule limits | J taken to pole end if the pole is longer | 12mR class rules 2016, rule 36, https://www.sailing.org/tools/documents/12M2016CR290216-[20399].pdf |

Planform flags:
- **wm9 is oversized for its analogues.** The game kite is 44.5 m². The largest analogue is about 36 m² (Soling 36.4, J/24 35.3). Either the game class is closer to a bigger keelboat, or the kite should shrink by about 20%. That is a design call for the owner.
- **wm21 sits at the top of the 12mR range.** 294 m² is slightly above the about 284 m² that the rule allows with SHW = foot and a typical J of 7.32 m.
- **Melges 24 vs J/80:** the Melges kite is far squarer (leech/luff 0.96 vs 0.80 for the J/80 test kite). For the same luff, the clew flies much higher. Do not copy J/80 corner positions to wm7 without rescaling the leech.

---

## 4. wm7: Melges 24 asymmetric (53.5 m²)

**Flying shape.** Deparday et al. 2016 (D1) remains the best source. It is the only full-scale, photogrammetric, tabulated asymmetric data set in open literature, and the J/80 is the closest boat in size and type: 8 m sportsboat, asymmetric on a sprit, about 63 to 68 m² kite.
- I confirm it is the right base for wm7. I found nothing better for this size.
- I could not reopen table 3 (HAL/ENSAM blocked), so I do not repeat its values here; use the copy you have.

**Supporting full-scale context (D2, Motta 2015) [FS]:**
- The J/80 and Stewart 34 kites gave maximum drive force at AWA 90° to 100°.
- Side force falls almost linearly with AWA.
- Suction peak is at 5 to 10% chord on the lower stripes and moves to the leading edge higher up.
- Trimmers kept the kites on the verge of luffing. The largest pressure scatter was in the first 10% of chord because the luff kept folding.

**Planform (section 3):** SLU 11.59, SLE 11.08, SHW 5.86, SFL 6.30, TPS 4.106 m from the mast face.

**How to apply the J/80 data**
1. Keep the J/80 camber, draft and entry angle per height fraction as they are (non-dimensional).
2. Build chords from the Melges planform. Width at height fraction h is interpolated between SFL (h=0), SHW (h=0.5) and the 3/4 width (class max 3.70 m).
3. Corner positions: scale the J/80 tack-to-clew displacement by the foot length ratio (6.30 / J/80 foot). The clew height comes from the Melges leech length, not the J/80 one.

**Missing:** Melges 24-specific flying shape. None published.

---

## 5. wm10: 10 m shorthanded offshore A2 (100.5 m²)

**Best flying shape:** J/80 [FS] (D1) scaled to the Figaro 3 / Sun Fast 3300 planform. The planforms have nearly the same non-dimensional proportions: SHW/SFL about 0.98 to 0.99 here.

**Second source, full-scale but figures only:** Stewart 34 kite SS34 (D2, D3) [FS].
- Boat and sail: 10.44 m LOA, kite 88.6 m², luff 13.2 m, leech 12.26 m.
- VSPARS stripe widths at 1/4, 1/2, 3/4 and 7/8 height: 8.63, 8.0, 5.4 and 2.9 m.
- Sections are only plotted, not tabulated (thesis section 6.3 and appendix B; read).
- Run range: AWA about 70° to 120°. Maximum drive force at 95° to 98°, with CFX up to about 1.6 and CFZ about 0.5 at 98°.
- Starboard runs were eased more than port runs, and the luff folded more often.
- Useful for **corner and stripe-width proportions** at this size; not for section numbers.

**Planform:** Figaro 3 A2 (ORC) SLU 16.02, SLE 13.74, SHW 9.08, SFL 9.19, TPS 5.66. Class40 has no spinnaker limits (sprit ≤ 2.0 m beyond hull, pole forbidden).

**Sailmaker guidance** for an A2 [SM]:
- Mid girth ≥ 100% of the foot: Quantum, Cruising World, https://www.cruisingworld.com/choosing-your-sail-inventory-downwind-sails
- Kemp: 90 to 100%, AWA 115° to 165°, https://kempsails.com/yacht-sails/racing-sails/racing-offwind-sails/offwind-racing-asymmetric-spinnaker/
- UK Sailmakers: A2 is a running sail at AWA 105° to 155°.
- Seahorse (Oct 2023): runners have deeper, rounder aft sections; reachers are flatter and straighter aft. A running sail can have a 105% SMG/SF. https://www.seahorsemagazine.com/article/october-2023/unravelling-the-mystique
- **No sailmaker publishes a depth percentage.**

**Missing:** any measured shape for a Figaro, Class40 or Sun Fast kite.

---

## 6. wm12 (J/122, 155.5 m²) and wm16 (TP52, 268.5 m²): grand-prix A2

### 6.1 AC33 benchmark asymmetric, measured flying shape at AWA 55° (D4) [WT]

**Provenance**
- Kite: an AC33-class asymmetric spinnaker built by North Sails NZ.
- Measurement: the flying shape was measured photogrammetrically in the Auckland twisted-flow wind tunnel. Viola and Flay 2011 say the CFD used "flying shapes ... detected using photogrammetric techniques". Optimum AWA is 55° (Viola and Flay 2009/2010; Bot et al. 2014).
- The shape was then 3D-printed as a rigid model. The DataShare file is that geometry at 1:106 scale (span 300 mm). The full-scale design area is 510 m².
- Arredondo-Galeana (thesis, read) gives 16° twist base to head for this geometry.
- Licensing and redistribution of the file: check the DataShare licence before shipping derived data.

**My slicing of `Spinnaker_high_twist_16deg.igs`**
- Method: the IGES file has 36 NURBS surfaces. I evaluated the two main sail faces only (the mounting bosses at about 23% and 75% height are excluded).
- Sections are horizontal cuts at fractions of vertical span. Chord is the longest straight line across the section.
- Camber is the maximum distance from the chord / chord. Draft is the position of maximum camber, measured from the luff (taken as the longer edge, 337 vs 316 mm).
- Twist is the chord angle relative to the 1/8-height section.
- Tag: **[WT], sections derived by me [EST-method]**.

| Height (fraction of span) | Chord (model mm) | Chord / chord at 1/8 | Camber % | Draft % from luff | Twist vs 1/8 section |
|---|---|---|---|---|---|
| 0.125 | 161.2 | 1.00 | 27.0 | 52.8 | 0.0° |
| 0.25 | 167.1 | 1.04 | 27.4 | 55.1 | +3.0° |
| 0.333 | 166.6 | 1.03 | 26.6 | 55.3 | +5.4° |
| 0.50 | 160.3 | 0.99 | 23.4 | 52.9 | +10.2° |
| 0.667 | 133.7 | 0.83 | 19.4 | 50.9 | +12.9° |
| 0.75 | 110.2 | 0.68 | 17.4 | 51.0 | +14.0° |
| 0.833 | 82.1 | 0.51 | 15.9 | 49.4 | +14.9° |
| 0.875 | 66.7 | 0.41 | 15.4 | 49.4 | +15.4° |
| 0.95 | 28.7 | 0.18 | 14.3 | 49.2 | +16.4° |

Notes:
- A cut at 2% height catches only the tack region (chord 101 mm, camber 14%), because the asymmetric foot rises from tack to clew. It is not a foot section, so it is left out.
- Entry and exit angles could not be extracted reliably from the thick, bevelled rigid model. My curve fits gave values that are not physical near the head, so none are reported.
- Section girth / chord ratio [EST]: 1.17 at 1/4 height, 1.13 at 1/2, 1.08 at 3/4, 1.11 at 7/8. Use these to turn a planform width into a flying chord.
- This is a **reaching** shape (AWA 55°, close to the A3/A2 crossover).
- Twist is mostly in the upper half: 10° by mid height, 16° at the head.
- Compared with the J/80 at AWA 64°, check how your table 3 twist compares. If the J/80 shows more twist, that is consistent with full-scale vs a tight wind-tunnel trim. Viola and Flay 2011 also note a tighter trim was used on the water to stop collapse.

### 6.2 Carina (M&R 48), North Sails design shape at AWA 85° (D5) [CFD/design]

From Souppez and Viola 2024, tables 1-2 (read).
- **Boat and sail:** spinnaker 175 m², vertical span 16.27 m.
- **Design condition:** AWA 85°, boat speed 4.06 m/s, TWS 6.17 m/s at 10 m. The apparent wind rotates 7.81° and gains 0.87 m/s from the bottom to the top section.

| Trim | Mid-span camber | Draft | Angle of attack of mid-span chord to apparent wind |
|---|---|---|---|
| T1, designer's optimum | 31% | 50.9% | 33.62° |
| T2, clew moved 0.50 m aft (sheet shortened) | 28% | 50.9% | 38.10° |

- Use: a mid-span check for wm12 at a broad reach. A **0.5 m sheet change on a 175 m² kite moves mid-span camber by 3 points and AoA by 4.5°**, a handy trim sensitivity.
- Spinnaker type (asymmetric or symmetric) is not stated in the paper. The SYRF study ran both on this boat.

### 6.3 How to build wm12 and wm16

- **Reach (AWA 55° to 90°):**
  - wm16: use the AC33 sections (6.1) scaled to the TP52 planform. Linear scale √(268.5/510) = 0.73, but drive the chords from the TP52 SHW/SFL rather than from the AC33 widths.
  - wm12: the J/80 64° row and the AC33 table bracket the J/122 well. Mid-span camber about 23% (AC33, AWA 55°) vs 31% (Carina, AWA 85°) gives a sensible AWA trend.
- **Run (AWA 120° to 145°):** no grand-prix data. Borrow the J/80 124° shape, in non-dimensional form, and the J/80 64°→124° change in camber, twist and clew position. **This is a borrowed trend, not data for these boats.**
- **Missing:** SYRF Downwind Aero (D9) is the one source that would fill this. It has FSI shapes for a modern TP52 and a Swan 42 at AWA 45° to 150°. Peart 2022 (thesis, read, section 5.2) confirms the data set exists: TP52 A3 at AWA 45/65/85/105° at 12 kn, traveller centred, trimmed to neutral luff pressure. It is worth an email to SYRF asking whether the flying-shape geometry, and not just the coefficients, can be released.

---

## 7. wm9 (44.5 m²) and wm21 (294 m²): symmetric spinnakers on a pole

### 7.1 What exists

I searched specifically for symmetric data (IACC-era papers, Southampton/Wolfson, Milan, Kiel, Auckland theses).

**Not found in open, tabulated form:**
- Measured **flying** shape (camber/draft/twist per height) of a symmetric spinnaker.
- Three candidates exist but I could not read them:
  - Mausolf et al. 2011 (D10): symmetric spinnaker, 38 ft c/r, wind tunnel and full scale.
  - Richards, Johnson and Stanton 2001 (D12): IACC.
  - Hedges' Auckland ME work on the North Sails NZ symmetric kite of the Whitbread 60 *Winston*, cited in D8.

**Found, numeric:** the **Moore / Lasher-Richards parametric IACC symmetric series** (D6).
- Five rigid 1/25-scale models (0.8 m² each) used for wind-tunnel and CFD force tests across the whole AWA range.
- The surface is given in closed form (Peart 2022, appendix A, read):

  x = kx · Σ(n=0..4) (aₙ s³ + bₙ s) tⁿ  (lateral, luff to luff)
  y = ky · (t − 0.1)  (height)
  z = kz · Σ(n=0..3) (cₙ s² + dₙ) tⁿ  (depth; the belly is +z, i.e. downwind)
  with −0.5 ≤ s ≤ 0.5 and 0.1 ≤ t ≤ 1.0

| n | aₙ | bₙ | cₙ | dₙ |
|---|---|---|---|---|
| 0 | −0.75 | 0.658 | −0.76 | 0.601 |
| 1 | 6.89 | −1.021 | 1.44 | −0.312 |
| 2 | −31.39 | 5.119 | −5.01 | 1.285 |
| 3 | 43.77 | −5.881 | 4.31 | −1.566 |
| 4 | −18.62 | 1.164 | | |

| Sail | kx | ky | kz | Foot camber (Peart table 3.1) |
|---|---|---|---|---|
| I | 1.18 | 1.22 | 0.85 | 23.1% |
| II | 1.10 | 1.211 | 0.98 | 28.4% |
| III | 1.02 | 1.20 | 1.11 | 34.8% |
| IV | 0.97 | 1.178 | 1.21 | 39.8% |
| V | 0.93 | 1.155 | 1.30 | 44.6% |

**Check:** my evaluation reproduces Peart's foot cambers exactly (23.0, 28.5, 34.8, 39.8, 44.6%), so the equations are transcribed correctly.

- What these shapes are: **prescribed rigid shapes, not photographs of a flying cloth sail.**
- Forces: measured in the wind tunnel (Lasher and Richards 2007; Moore 2004; Peart 2018) with the sail rigid and untrimmed. "The variation of AWA is a change only in the angle of attack, without any trimming effect" (Peart 2022 p. 41).

### 7.2 Sections from the equations [WT-parametric, evaluated by me]

- Sections are horizontal (constant t) at fractions of vertical height.
- Chord: straight luff-to-luff distance. Camber: depth/chord. Draft: 50% by symmetry.
- Twist: **0°** by construction (every section is symmetric about the centre plane).
- Entry angle: tangent at the luff vs the chord (exit angle is the same).

| Height | Sail I camber / entry | Sail II | Sail III | Sail IV | Sail V |
|---|---|---|---|---|---|
| foot (0) | 23.0% / 54° | 28.5% / 59° | 34.8% / 64° | 39.8% / 67° | 44.6% / 69° |
| 1/6 | 21.5% / 53° | 26.6% / 59° | 32.5% / 63° | 37.2% / 66° | 41.7% / 69° |
| 2/6 | 23.3% / 68° | 28.8% / 72° | 35.2% / 75° | 40.3% / 77° | 45.2% / 78° |
| 3/6 | 24.9% / 78° | 30.8% / 81° | 37.7% / 82° | 43.2% / 83° | 48.4% / 84° |
| 4/6 | 25.1% / 75° | 31.1% / 78° | 37.9% / 80° | 43.5% / 81° | 48.7% / 82° |
| 5/6 | 24.0% / 64° | 29.7% / 69° | 36.3% / 72° | 41.6% / 75° | 46.6% / 76° |
| 0.95 | 23.0% | 28.4% | 34.7% | 39.8% | 44.6% |

The very high entry angles come from the cubic lateral term: the sections wrap round at the luffs like a horseshoe. Treat them as a property of this parametric family. They are plausible for a symmetric kite with curled luffs, but not validated.

**Width and height distribution (Sail II, typical)**

| Height | Chord / foot chord | Girth / foot girth | Luff-edge offset upwind of the foot luff point, / height |
|---|---|---|---|
| 0 | 1.00 | 1.00 | 0.00 |
| 1/6 | 1.04 | 1.03 | 0.00 |
| 2/6 | 1.06 | 1.08 | 0.01 |
| 3/6 | 1.07 | 1.13 | 0.05 |
| 4/6 | 1.01 | 1.07 | 0.11 |
| 5/6 | 0.74 | 0.76 | 0.22 |
| 0.95 | 0.30 | 0.31 | 0.32 |

**Series planform at model scale** (girths along the surface):

| Sail | Luff | Foot girth | SHW (girth at half luff) | SHW/SFL | Surface area | ORC formula area |
|---|---|---|---|---|---|---|
| I | 1.295 | 0.698 | 0.775 | 1.11 | 0.808 | 0.819 |
| V | 1.300 | 0.687 | 0.776 | 1.13 | 0.802 | 0.822 |

- At 1:25 this is a luff of about 32.4 m and about 500 m², i.e. IACC size.
- **The girth is almost the same across the series.** Sails I to V differ mainly in how deep the same cloth is set: the chord (clew-to-tack spread) shrinks as the depth grows.
- That gives a direct way to drive a symmetric kite from **pole and sheet spread at constant planform**. For a circular-arc section, girth/chord = θ/sin θ and camber = (1 − cos θ)/(2 sin θ). The series follows this: girth/chord 1.20 at 25% camber, 1.53 at 48% (Sail I and V at mid-height).
- The luff edges lean upwind (aft on a run) toward the head: about 16° (Sail I) to 25° (Sail V) from vertical at 95% height. This reads as the head sitting near the mast while the foot is held out at the pole and sheet. It is a model mounting geometry, so treat the lean as indicative, not measured.

### 7.3 How to build wm9 and wm21

- **Section family:** the Moore/Lasher shape, scaled by luff length.
  - wm21 (12mR, about 18.6 m luff): factor 18.6 / 1.30 = 14.3 on the model, i.e. about 1:1.75 of the IACC original.
  - wm9: scale to the class luff (J/24 8.13 m, Soling 7.50 m, Dragon about 7.0 m).
- **Planform correction:**
  - Analogue SHW/SFL is 1.00 to 1.06 (J/24 1.00, Soling 1.05, Dragon about 1.06) vs 1.11 to 1.13 in the series.
  - Narrow the upper half slightly, or accept the IACC-style shoulder for wm21. 12mR kites of the 1980s were IACC's direct predecessors, and the 12mR rule only sets a minimum mid width.
- **Depth by point of sail:**
  - Run: use the deeper members, Sail III to V (35% to 48% at mid height).
  - Reach: use Sail I to II (22% to 31%), with the pole forward and squared less.
  - This is **my mapping, not measured**: the series was tested at a fixed shape across AWA. It is consistent with the asymmetric data, where the J/80 and AC33 kites are flatter on a reach than on a run.
- **Twist:** none in the data. A flying symmetric kite does twist, since the leeward clew is free on the sheet.
  - Borrow the AC33 asymmetric twist distribution for the leeward half at reaching angles: 0° at 1/8 height, about 10° at mid height, about 16° at the head.
  - Use near-zero twist dead downwind, where both clews are held symmetrically.
  - **This is a borrowed estimate [EST].**
- **Missing:**
  - Any measured symmetric flying shape.
  - Any 12mR spinnaker dimensions for a named boat.
  - Any data for keelboat-class kites (Dragon, Etchells, Soling, J/24) beyond class-rule planforms.

---

## 8. Corner positions in flight

| Source | What moves | Value | Quality |
|---|---|---|---|
| Deparday et al. 2016 (D1) | J/80 clew, AWA 64° → 141° | 2.3 m forward, 1.4 m higher (as you quoted from the paper) | [FS] |
| Motta 2015 thesis section 4.3 (D2) | VO70 model A2, AWA 60° → 120°, wind tunnel | "The clew position moves forward, outwards and upwards with increasing AWA". The FEPV prediction agreed with string-and-ruler measurements within about 2% (fig. 4.7, plotted only). A3 at 60°/80°: clew x, y, z prediction errors < 5% (table 4.6). | [WT] |
| Augier et al. 2021 (D7) | Asymmetric model at AWA 100°, sheet eased from over-trimmed to the verge of curling | "The sheeting point moves forward and upward when easing the sail, when the luff is sliding windward" | [WT] |
| Souppez and Viola 2024 (D5) | Carina, AWA 85° | Clew 0.50 m aft (sheet in) → mid-span camber 31% → 28%, AoA +4.5° | [CFD/design] |
| Moore/Lasher series (section 7.2) | Symmetric head relative to foot | Luff edge near the head is 0.16 to 0.25 × height upwind of the foot | [WT-parametric] |

Head position in flight: no study tabulates head sag or offset for asymmetrics. Deparday's full 3D shapes contain it; check whether table 3 or the figures give head coordinates.

---

## 9. Scaling recipe (no invented numbers)

1. **Keep non-dimensional:** camber %, draft %, twist relative to the foot section, entry angle, all per **height fraction of luff**.
2. **Chords from planform:** get the width at each height from the target SFL, SHW and (where given) the 3/4 width. Convert girth to flying chord with the source's girth/chord ratio:
   - AC33: 1.08 to 1.17.
   - Moore: circular-arc relation in 7.2.
   - J/80: derive from your table 3 camber with the same arc relation.
3. **AWA:** interpolate between the source's two AWAs (J/80: 64°/124°; AC33: 55° only; Carina: 85° only). Outside that range, hold the end value. Do not extrapolate.
4. **Corners:** scale the clew displacement with AWA by the foot length (SFL target / SFL source). Scale the clew height by the leech length.

---

## 10. What I could not read

- **Deparday 2016 (D1) full text, and Deparday's 2016 PhD thesis.** Blocked by HAL bot protection, sam.ensam.eu 403 and CORE Cloudflare. A browser session would get them. The thesis may have more AWAs than table 3.
- **Bot et al. 2014** Ocean Eng. 90:84-92 (rigid AC33 model, pressures): blocked the same way. The Edinburgh copy returned HTML.
- **Motta et al. 2014 Ocean Eng. (D3)** and **Viola and Flay 2009 IJSCT**: abstracts only.
- **Mausolf et al. 2011 (D10)**, **Graf and Müller 2009 (D11)**, **Richards et al. 2001 (D12)**, **Lasher et al. 2005** *The aerodynamics of symmetric spinnakers* (J. Wind Eng. Ind. Aerodyn. 93:311-337; 12 parametric symmetric models): paywalled, no open copy found.
- **Hansen 2006 Auckland PhD thesis** (wind tunnel spinnaker techniques): ResearchSpace returns 401 (restricted).
- **SYRF Downwind Aero Moments & Forces reports (D9):** not found online.
- **Augier et al. 2021 STEP flying-shape geometries:** the Google Drive link in the paper is dead (404).
- **Cirello et al. 2021** JMSE 9:624 (small-yacht gennaker FSI): MDPI and IRIS both returned 403.
- **ORC certificates on data.orc.org** (now behind a human check) and **IRC certificates**: TP52 Red Bandit and Sun Fast 3300 planforms are search snippets only. They are arithmetic-consistent but unverified.

## 11. Files

- AC33 geometry: `dl/geo/g/Geometries/IGS_format/*.igs`
- Slicing tools: `tools/igs.py`, `tools/igs2.py`, `tools/sect.py`, `tools/girth.py`
- Moore series evaluation: `tools/moore.py` (pure Python)
- Motta thesis text: `dl/motta/motta.txt`
- Peart thesis: `dl/rs/peart.pdf`

All paths are under /private/tmp/claude-501/-Users-markokuret-Code-windmark/206e1774-4fa8-48b9-b22f-38fad25d857e/scratchpad/.
