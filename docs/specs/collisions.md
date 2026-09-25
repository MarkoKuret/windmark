# Collisions

Contact between boats, marks, course objects, fixed obstacles and land: detection on 2-D shapes in the water plane,
a simple impulse response that fits the boat model (`boat.md`), and the contact events the rules engine reads
(`rules.md`). Runs in tick step 6 (`conventions.md` §4.1), after every boat has moved.

## 1. Principles

- **2-D**: everything that can touch a boat is at the waterline, so shapes are outlines in the water plane.
  Rigs and sprits do not collide (a sprit touching another boat is not detected).
- **Convex boats**: a hull is a convex polygon; marks are circles; course objects and fixed obstacles are circles
  or convex polygons; land is arbitrary polygons.
- **Resolve, then report**: penetration is removed by moving the boats apart, closing speed by an impulse split
  into the boat's forward speed, a decaying lateral "contact velocity" and a yaw kick. Every contact is reported.
- **Deterministic order**: contacts are found and resolved in a fixed order, one pass per tick.

## 2. Shapes

### 2.1 Boat hull
`dynamics.collision.outline` in the performance file (`data_format.md` §4.2): a convex polygon in the body frame
(x forward, y port), counter-clockwise in `(x, y)`, 6–32 vertices, written by the boat generator from the hull.
Validated at load: strictly convex, counter-clockwise, containing the origin.

Reference construction (the generator's rule): with `x_s`, `x_b` the body x of the transom and the stem,
`L = x_b − x_s`, `B` the maximum beam, `T` the transom width and `s_m` the station of maximum beam (fraction of `L`
from the transom, default 0.45), the half-breadth at station `s ∈ [0, 1]` is
```
s <= s_m : b(s) = T/2 + (B/2 − T/2) · (1 − (1 − s/s_m)²)
s >  s_m : b(s) = (B/2) · (1 − u^1.8),  u = (s − s_m)/(1 − s_m)
```
sampled at `s = 0, 0.15, 0.3, s_m, 0.6, 0.75, 0.87, 0.95` on both sides plus the stem point `(x_b, 0)`.

Per class at load: `r_hull` = the largest vertex distance from the origin (broad phase), `mass` =
`dynamics.collision.mass` (kg, sailing displacement with crew), `yaw_inertia = mass · k²` with
`k = dynamics.collision.yaw_gyration` (reference 0.28 · LOA).

World vertices each tick: with `f = (sin ψ, cos ψ)`, `p = (−cos ψ, sin ψ)` (bow, port),
`w_k = (pos + x_k·f) + y_k·p` in vertex order.

### 2.2 Course objects and obstacles
From the course (`race.md`) and the venue (`data_format.md` §6.5):

| kind | shape | data |
| --- | --- | --- |
| `mark` | circle | centre, radius (at least 0.8 m; reference 0.8 m for an inflatable, 1.5 m for a large buoy) |
| `course_object` (committee and mark boats; every buoy, including pin end and gate buoys, is a `mark`) | circle or convex polygon with a heading | course spec |
| `obstacle` (moored boats, piers, rocks) | convex polygon or circle | venue file |
| `land` | polygon, counter-clockwise, interior = land; islands are separate polygons | venue file |

All of them are static (they never move and have infinite mass).

## 3. Detection

### 3.1 Order
Contacts are collected into one list in this order, on the positions after all boat steps of the tick:
1. boat–boat pairs `(i, j)`, `i < j`, ascending `i` then `j`;
2. for each boat ascending: marks and course objects in course order;
3. for each boat ascending: venue obstacles in file order, then land polygons in file order.
Only boats with `collides = true` take part (the race layer clears it for boats that are not racing, `race.md`).
Each pair gives **at most one** contact.

Broad phase: a boat pair is tested only if `|pos_i − pos_j| < r_i + r_j`; a boat and a circle only if
`|pos − centre| < r_hull + radius`; polygons use their bounding circle likewise. Land uses a spatial index built
at load; it must return the same contacts as testing every edge.

### 3.2 Polygon vs polygon (separating axes)
For boat (or polygon) `A` and polygon `B`, both convex, counter-clockwise:
```
best = +inf
for each edge of A (in order), then each edge of B (in order):
    n = unit outward normal of the edge
    project both polygons on n: [minA, maxA], [minB, maxB]
    o = min(maxA - minB, maxB - minA)
    if o <= 0: no contact, stop
    if o < best: best = o ; axis = n ; from_A = (edge belongs to A)
depth = best
normal = axis, flipped if dot(axis, centre_A - centre_B) < 0     // points from B toward A
point  = from_A ? the vertex of B with the largest projection on +normal    (the B vertex deepest inside A)
                : the vertex of A with the largest projection on -normal    (the A vertex deepest inside B)
```
Vertex ties go to the lower index. `centre` is the boat's `pos` (its hull reference point) or the polygon's
centroid.

### 3.3 Circle vs polygon
Circle `(c, r)`, polygon `A`:
```
if c is inside A (all edge tests <= 0):
    e = the edge with the smallest distance from c to its line (lowest index on ties)
    normal = -outward_normal(e)            // from the circle toward the inside of A
    depth = r + dist(c, line(e)) ; point = c
else:
    q = the closest point to c on A's boundary (lowest edge index on ties)
    d = |q - c| ; if d >= r: no contact
    normal = (q - c) / d ; depth = r - d ; point = q
```

### 3.4 Boat vs land
For boat `A` and land polygon `L`:
```
candidates:
  (a) each vertex w of A inside L (crossing-number test, below):
        e = the edge of L nearest to w ; depth = dist(w, e) ; normal = outward normal of e (toward water) ; point = w
  (b) each vertex q of L inside A:
        e = the edge of A nearest to q ; depth = dist(q, line(e)) ; normal = -outward_normal(e) ; point = q
contact = the candidate with the largest depth (first found on ties: (a) before (b), then by index)
```
Crossing number of point `p` against `L` (half-open rule, deterministic on vertices):
edge `(a, b)` crosses when `(a.y > p.y) != (b.y > p.y)` and
`p.x < a.x + (p.y − a.y) * (b.x − a.x) / (b.y − a.y)`; `p` is inside when the count is odd.
Distances to edges use the clamped projection on the segment.

### 3.5 Tunnelling
The fastest boats move under 1.2 m per tick and the smallest shape is about 1.6 m across, so discrete tests are
enough; there is no swept test.

## 4. Response

Constants:

| name | value | meaning |
| --- | --- | --- |
| `SLOP` | 0.02 m | penetration left alone |
| `PUSH` | 0.8 | fraction of the remaining penetration removed per contact |
| `PUSH_MAX` | 0.5 m | largest correction per contact |
| `REST_BOAT`, `REST_MARK`, `REST_FIXED` | 0.2, 0.3, 0.1 | restitution boat–boat, boat–mark/course object, boat–obstacle/land |
| `FRICTION_BOAT`, `FRICTION_FIXED` | 0.3, 0.5 | Coulomb friction coefficients |
| `YAW_KICK_MAX` | 1.0 rad/s | clamp of `contact_yaw_rate` |
| `CONTACT_KEEP` | 0.9 per tick | decay of the contact velocity and yaw rate (`boat.md` §5.10; e-folding time 0.47 s) |

For each contact in list order (a single pass; each contact sees the velocities left by the previous ones):

### 4.1 Separate
```
corr = min(max(depth - SLOP, 0) * PUSH, PUSH_MAX)
boat-boat: A.pos += normal * (corr * mB/(mA+mB)) ; B.pos -= normal * (corr * mA/(mA+mB))
fixed:     A.pos += normal * corr
```

### 4.2 Impulse
Ground velocity of a boat: `V = (v·f + current) + contact_v` (`boat.md` §5.10); fixed objects have `V = 0`.
```
vr = V_A - V_B ; vn = dot(vr, normal)
if vn < 0:                                              // closing
    inv = 1/mA + (boat-boat ? 1/mB : 0)
    j  = -(1 + e) * vn / inv
    t  = (-normal.y, normal.x) ; vt = dot(vr, t)
    jt = clamp(-vt / inv, -mu*j, mu*j)
    J  = normal*j + t*jt                                 // impulse on A (N·s); -J on B
    apply(A, +J) ; if boat-boat: apply(B, -J)
apply(boat, J):
    dV = J / m
    dv = dot(dV, f)                                      // forward part
    v  = v + dv
    contact_v = contact_v + (dV - f*dv)                  // the rest, over the ground
    r = point - pos
    torque = r.x*J.y - r.y*J.x                           // counter-clockwise positive
    contact_yaw_rate = clamp(contact_yaw_rate - torque / yaw_inertia, -YAW_KICK_MAX, YAW_KICK_MAX)
```
(the minus turns the counter-clockwise torque into a clockwise heading rate). Positions and velocities changed
here are the ones stored at the end of the tick; their effect on heading and track starts with the next boat step.

What it feels like: two boats touching bounce apart gently (restitution 0.2), the one hit in the side is pushed
sideways and spun a little, a boat that rams another loses most of its forward speed. A boat pressed against land
or a pier is held off it: the push-out removes the penetration each tick, the impulse removes the closing speed,
friction slows it along the shore. There is no damage and no special grounding state.

## 5. Contact events

Every resolved contact produces one event, in list order:

| field | meaning |
| --- | --- |
| `tick` | tick index |
| `boat` | index of boat `A` |
| `other_kind` | `boat`, `mark`, `course_object`, `obstacle`, `land` |
| `other` | boat index, mark or object index in the course, obstacle or land index in the venue |
| `point`, `normal`, `depth` | as detected |
| `closing_speed` | `max(0, −vn)` before the impulse, m/s |
| `impulse` | `j` (0 when not closing) |
| `begin` | true if the same pair had no contact in the previous tick |

The per-pair "in contact last tick" flags are state (a sorted list of pair keys, serialised after the boats).
Consumers: the rules engine (boat–boat contact, touching a mark or a course object, `rules.md`) in tick step 1 of
the next tick, the audio and camera shake (`begin` with `closing_speed`), replays.

## 6. State

| name | meaning |
| --- | --- |
| per boat: `collides` | set by the race layer |
| contact pair set | pairs in contact at the end of the last tick, for `begin` |

The boat values changed by collisions (`pos`, `v`, `contact_vx/vy`, `contact_yaw_rate`) are boat state
(`boat.md` §3).

## 7. Tests

1. Head-on at 3 m/s each, equal masses: after the contact the closing speed is 0.2 × the initial one and both
   boats' forward speeds dropped by the same amount.
2. T-bone: the struck boat gains lateral `contact_v` and a yaw rate in the direction of the push; both decay to
   under 10 % within 1.1 s.
3. A boat sailing into land at 45° slides along it without passing through for 30 s.
4. Mark touch: a boat passing 0.5 m inside a mark's radius produces exactly one `begin` event.
5. Rotating the vertex list of a land polygon (a different start vertex) does not change whether a contact is
   found or its depth.
