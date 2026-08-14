# Rear Implement Architecture — Three-Point Hitch and Direct-Drive PTO

## 1. What this decision actually does to the machine

Adding a Category 1/2 three-point hitch and a live direct-drive PTO stops this
being a track loader with an extra feature. It becomes a **compact rubber-track
tractor with a loader**, and it should be designed and sold as one.

That is a bigger claim than it sounds, and it is a good one. The compact utility
tractor with a front loader is one of the best-selling equipment categories in
North America — and **every single one of them is on wheels and gets stuck.**
CUTs are poor in mud, poor on slopes, and poor on soft ground, which is most of
what a small farm, vineyard, orchard or municipal yard deals with in three
seasons out of four.

A tracked machine with a real loader, a real hitch and a real PTO is not a
crowded segment. It is an empty one.

**The honest counterweight:** rubber tracks and pavement do not get along. A CUT
drives itself down the road between fields; this machine will need a trailer for
anything beyond a short move. For a single-property operation that is fine and
often irrelevant. For a contractor working scattered sites it is a genuine
objection, and you should decide now whether that customer is in your market or
not, because the answer changes how you spec the undercarriage.

---

## 2. The architectural fork: where does the engine point?

This is the decision. In a conventional CTL the engine sits **transverse at the
extreme rear**, driving the tandem hydrostat pumps directly. That is precisely
the volume the hitch and PTO need. There is no version of this where both fit
as-is.

| | **A. Longitudinal engine** | **B. Transverse + right-angle drive** | C. Hydraulic PTO |
|---|---|---|---|
| PTO path | Straight off the crank, rearward | 90° gearbox | Motor driving a stub shaft |
| Driveline losses | Lowest | Gearbox loss + noise | 15–20% — significant |
| PTO clutch | Inline wet clutch, straightforward | Packaging-constrained | N/A |
| Pump drive | Off the front of the crank — standard practice | Unchanged from CTL | Unchanged |
| Frame impact | **Substantial — new architecture** | Moderate | Minimal |
| Is it "direct drive"? | Yes | Yes | **No** |

**Recommendation: A, longitudinal engine.** This is how every tractor on earth
is laid out, and the reason is exactly the problem you are solving. The crank
drives rearward through a PTO clutch to the output shaft; the front of the crank
drives a pump drive gearbox for the hydrostats and the work pump. Clean, proven,
serviceable.

Option B works and is cheaper in frame terms, but you are buying a gearbox, its
noise, its losses and its packaging headache to preserve a layout you are
abandoning anyway. Since you are moving things regardless, move them properly.

Option C is out — you specified direct drive, and you were right to. Hydraulic
PTO cannot hold speed under shock load the way ag implements demand, and the
losses come straight out of the number your customers shop on.

**Good news for the control system:** none of this touches the propel logic. The
hydrostats do not care whether they are driven off the front or the back of the
crank. Everything in `src/st/` survives this change intact.

---

## 3. The consequence nobody expects: engine size

**PTO horsepower is the number ag buyers compare, and it will size your engine.**

A CUT-class implement — a 6 ft rotary cutter, a tiller, a snowblower — wants
40–50 hp at the shaft. That is *in addition to* the loader hydraulics, the
hitch, rear remotes, and the propel circuit. The 74 hp V3307 that was
comfortable for a pure CTL is tight the moment you hang a PTO off it, and
"74 gross / 41 PTO" is a specification that loses to a Kubota L-series on a
dealer lot.

Plan on stepping up to roughly the **95–110 hp class** — Kubota V3800 or
equivalent — and revisit the sizing in `01-hardware-selection.md` before you
open the engine account. This is exactly why that conversation should happen
first: it has the longest lead time and it is now on the critical path of a
spec change.

---

## 4. Weight and balance — a genuine synergy

A rear implement is **ballast where the loader needs it**. Loader lift capacity
on this class of machine is limited by forward tipping, and a 3-point hitch
carrying a box blade or a rotary cutter directly increases the tipping load.

You were going to carry rear counterweight anyway. Now some of it does work.

The hitch, PTO gearbox, clutch and rear remotes will add somewhere in the range
of 400–800 lb at the extreme rear. Against the trailer-weight ceiling discussed
in `04-crossover-concept.md`, that is real, and it makes the "buy capability
with software, not ballast" discipline more important rather than less.

---

## 5. Rear hydraulics

A 3-point without remotes is half a hitch. Ag implements expect **selective
control valves** — plan two pairs minimum, three if you can. A hydraulic top
link is a small cost and an outsized quality-of-life feature; it is the first
thing owners retrofit.

These are additional PVG 32 sections, commanded over CAN exactly like the loader
and aux sections. The architecture already handles them.

---

## 6. Two regulatory regimes, not one

**This is the flag worth raising loudest, because it is easy to miss and
expensive to discover late.**

A track loader is earth-moving machinery. A machine with a PTO and a three-point
hitch is *also* agricultural machinery. You are now potentially in scope for two
standards families at once:

| | Earth-moving | Agricultural |
|---|---|---|
| Machine safety | ISO 20474 / EN 474 | ISO 4254 |
| Control system safety | ISO 13849-1, ISO 15998 | **ISO 25119** |
| Implement bus | — | ISO 11783 (ISOBUS) |
| PTO | — | ISO 500 (dimensions, rotation, guarding) |

ISO 25119 is the agricultural functional-safety standard and it is *not* the
same document as ISO 13849 — different structure, different terminology,
different assessment route. Which one governs your PTO engagement chain is a
question for a compliance consultant, and the answer affects controller
selection, development process and documentation from here forward.

**Get this scoped before you write the safety chain, not after.** As with
everything else in the safety column, treat these standard numbers as items to
confirm rather than as citations.

### PTO safety is not a formality

PTO entanglement is among the most lethal hazards in agriculture, and it kills
people who have operated machinery for forty years. Design requirements, not
suggestions:

- Master shield and full driveline guarding, integral to the machine
- **PTO cannot engage without a fresh operator request** — never automatically
  on sit-down, never automatically on fault clear. `FB_PtoControl` enforces this
  with the same latch pattern as propel neutral-before-enable.
- Operator leaves the seat → PTO stops. If you later want a stationary-PTO
  override for augers or generators, that is a separate, deliberately awkward,
  clearly-indicated mode — not a default behaviour.
- There is a maximum permitted stopping time for a PTO after a stop command.
  Confirm the figure that applies in your market and **design the brake to
  meet it**, because the clutch alone will not.

---

## 7. Where this gets interesting: draft control meets traction control

Here is the payoff, and it falls out of work already done.

Classic Ferguson draft control senses the pull on the implement and raises the
hitch slightly as draft rises, transferring implement weight onto the tractor
to restore traction. Every tractor built since 1940 does some version of it.

**But draft force is only a proxy for what the operator actually cares about,
which is slip.** Tractors measure draft because measuring slip was hard in 1940.

`FB_TractiveControl` already measures slip, for the rimpull limiting in
`04-crossover-concept.md`. So this machine can close the loop on the real
variable:

```
   slip detected  ──►  raise hitch slightly  ──►  weight transfers to tracks
        ▲                                                    │
        └──────────────  slip falls  ◄───────────────────────┘
```

That is **slip-referenced draft control**, and combined with rimpull limiting it
gives the machine two independent levers on traction that no tractor and no
track loader has together:

- too much slip, implement in the ground → raise the hitch (weight transfer)
- too much slip, no implement → cap rimpull (refuse to spin)

Both are implemented. `FB_HitchControl` takes the slip ratio directly from
`FB_TractiveControl` and blends a slip term into the conventional draft loop, so
you get standard draft behaviour that a tractor operator recognises, plus a
correction on the variable that actually matters.

---

## 8. ISOBUS — the ecosystem decision

`01-hardware-selection.md` reserved CAN3 as an attachment bus. With a three-point
hitch, **that bus should be ISOBUS (ISO 11783)** at the rear.

The argument is the same as the attachment-ID argument for the front, but
stronger: an ISOBUS-capable machine runs *any* compliant implement through your
display, and ag implement makers have already done the work. Refusing ISOBUS
means every implement is dumb, forever.

The cost is real — a certified stack, licensing, conformance testing — and it is
not a launch-day requirement. But **wire for it now.** Bus topology, connector
position and the rear power budget are cheap today and expensive after tooling.

---

## 9. Control blocks added

| Block | Function |
|---|---|
| `FB_PtoControl` | Modulated clutch engagement, 540/540E/1000 speed management, engine-droop-aware ramp hold, auto-PTO on hitch raise, interlocks with mandatory re-request |
| `FB_HitchControl` | Position, draft and blended control, slip-referenced draft augmentation, rate-of-drop, working-depth memory, height limit |
| `FB_HeadlandSequence` | Two-press headland turn: raise and stop, then lower and resume |

---

## 10. Open questions for you

1. **Hitch category** — Cat 1 covers most compact implements; Cat 2 opens up
   bigger tools and more of the used-implement market. Cat 1 with Cat 2 pin
   options is the usual hedge.
2. **PTO speeds** — 540 only is simplest. 540/540E is a fuel-economy story that
   sells well. 1000 matters mostly for larger implements you may not be
   targeting.
3. **Ground-drive / creeper range.** Tillage and planting want ground speeds
   below what a hydrostat sized for loader work delivers comfortably. The creep
   mode already in `PRG_Propel` covers part of this, but if row-crop work is in
   scope, say so — it changes the hydrostat sizing conversation with Danfoss.
4. ~~**Mid-mount PTO?**~~ **DECIDED: no mid-mount PTO.** See below.

---

## 11. Decided: no mid-mount PTO

The positioning argument is the deciding one. This machine's credibility rests
on digging and pulling, and a mid-mount deck signals lawn tractor to exactly the
buyer you need to take it seriously. **Category confusion kills a new machine
faster than a missing feature does** — a machine that is legible as one thing
beats a machine that is arguably two.

The engineering falls the same way, which is convenient:

- **The belly becomes a flat sealed skid plate.** On a tracked machine working
  in brush, mud and crop residue, an uninterrupted underside is worth real
  money in debris packing and undercarriage wear. A mid drive puts shafts,
  guards and grease points in the worst possible place to service.
- **Ground clearance and approach angle stay clean.** A mid drive compromises
  both, on a machine whose whole pitch is going where wheels cannot.
- **Frame centre stays free** for fuel and hydraulic tank volume — which the
  bigger engine and the PTO circuit both now need.
- **One less drive path, clutch, guard and failure mode**, and the cost that
  goes with them.

**Nothing real is lost.** Brush and field mowing move to a rotary cutter on the
three-point, which is where that work belongs anyway, and a rear-discharge
finish mower on the hitch covers the rest. What gets given up is *lawn* mowing
positioning — which is precisely the thing worth giving up.

No control-system impact: no mid PTO means no second clutch, no second speed
supervision, no additional interlock path. `FB_PtoControl` supervises one shaft.
