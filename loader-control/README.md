# Compact Track Loader / Utility Tractor — Machine Control System

## The machine, in one paragraph

A rubber-tracked utility machine in the 11,000–13,000 lb class with ~100 hp,
carrying a front loader, a Category 1/2 three-point hitch and a live
direct-drive 540 PTO. It lifts around 3,000–3,500 lb, pulls 9,000–11,000 lbf at
the drawbar, and dozes with a quick-attach blade. It is deliberately light
enough to trailer under the CDL threshold and deliberately over-powered for its
weight, because horsepower is what makes it versatile and weight is what makes
it a specialist.

**Positioning:** the compact utility tractor with a loader is one of the
best-selling equipment categories in North America, and every one of them is on
wheels and gets stuck. This is that machine, on tracks, that can also dig, doze
and grade.

---

## Why the design holds together

Every decision on this machine reinforces the others rather than fighting them.
That coherence is itself the competitive advantage, and it is the thing to
protect:

```
   no mid-mount deck ──► ag positioning, credible as a work machine
                              │
   longitudinal engine ───────┼──► PTO and hitch fit; propel logic untouched
                              │
   reduced lift capacity ─────┼──► weight becomes traction, not counterweight
                              │         │
                              │         ├──► better pull, better push, lower CG
                              │         └──► under the CDL threshold: BOTH markets
                              │
   long track contact ────────┼──► stability, flotation, grading quality
                              │         └──► scrub cost cancelled by crawler steering mode
                              │
   three-point hitch ─────────┴──► doubles as the reconfigurable ballast system
```

And the control system ends up with **three coordinated levers on traction**
where competitors have zero or one: cap rimpull, raise the rear implement,
raise the front blade. Same problem, three actuators, deliberate ordering.

---

## Locked decisions

| Area | Decision | Where |
|---|---|---|
| Electrical architecture | CAN-centric — grips, valves, display, engine on CAN | `01` |
| Controller | IFM CR711S, CODESYS, IEC 61131-3 | `01` |
| Hydraulics | Danfoss H1 hydrostat, PVG 32 + PVED-CC | `01` |
| Engine | Longitudinal, **Cummins B4.5** de-rated to 100–110 hp. Bay designed to also accept Kubota V3800 | `09` |
| Rear | Cat 1/2 three-point, direct-drive 540 PTO | `05` |
| Mid-mount PTO | **No** | `05` §11 |
| Capacity | ~3,000–3,500 lb ROC, 11,000–13,000 lb operating | `07` |
| Ballast | Reconfigurable, via the three-point | `06` §3 |
| Dozer blade | Quick-attach on the loader arms | `07` §3 |
| Operator interface | ISO pattern default, configurable button bindings | `02` |

---

## Still open

| Question | Blocks |
|---|---|
| Slot geometry — the boom angle at which the push pin disengages | `FB_DozerMode` needs this one number; everything else follows |
| Aux section count — a 6-way blade needs three more proportional functions | Valve bank order |
| Hitch category — Cat 1, or Cat 1 with Cat 2 pin options? | Hitch design |
| PTO speeds — 540 only, or 540/540E? | Gearbox spec |
| Row-crop work in scope? | Hydrostat sizing conversation with Danfoss |
| Undercarriage — rigid or suspended/oscillating? | Grading precision vs rough-ground traction |
| Lift geometry — vertical confirmed? | Self-level coupling table |
| Prototype or production-intent safety approach? | Controller partition, development process |

---

## Control software

Platform-neutral IEC 61131-3 Structured Text. All machine logic lives in
`src/st/`; all platform binding lives in `src/hal/`. A controller change is a
HAL rewrite, not a redesign — but that only stays true if it is **proven once
during development**, not first attempted during a shortage.

### Built

| Block | Does |
|---|---|
| `FB_AxisConditioning` | Dual-channel plausibility, step-free deadband, expo, asymmetric ramps |
| `FB_DriveMixer` | Skid ⇄ crawler steering blend, ratio- vs speed-preserving saturation |
| `FB_TractiveControl` | Rimpull ceiling, slip control, fused ground-speed estimate |
| `FB_AntiStall` | Engine droop derate, propel cut before work hydraulics |
| `FB_ProportionalOut` | Solenoid threshold compensation, coil selection, dither |
| `FB_ButtonInput` | Debounce, short/long/double/hold, opt-in double-tap latency |
| `FB_FunctionDispatch` | Binding table scan, bounds-checked against corrupt NVM |
| `FB_LoaderControl` | Self-level both directions, return-to-dig/carry, float, height limit, shake |
| `FB_AuxControl` | Proportional aux, modulating detent, high-flow interlocks, pressure protection |
| `FB_LoadMoment` | Payload weighing, pitch-corrected stability margin, progressive raise limit |
| `FB_BladeControl` | Cross-slope hold (2D grade), blade load control |
| `FB_DozerMode` | Push-link load-path detection, rimpull scheduling by boom height |
| `FB_CoolingFan` | Variable-speed fan, automatic reversing purge with hot-machine inhibit |
| `FB_ReservoirGuard` | Temp-compensated level, staged inhibit keeping mobility, leak detection |
| `FB_PtoControl` | Three-phase clutch engagement, droop-aware ramp, mandatory re-request |
| `FB_HitchControl` | Position, draft, and slip-referenced draft augmentation |
| `FB_HeadlandSequence` | Two-press headland turn, correctly ordered both directions |
| `PRG_Propel` / `PRG_Loader` / `PRG_Rear` | 10 ms and 50 ms task wiring |

### Gated on a running prototype

Every calibration constant in the codebase is a placeholder — coil currents, PI
gains, droop thresholds, linkage coupling, load-moment geometry tables. They
cannot be derived on paper. Beyond those:

- Dig assist (needs real propel-pressure data)
- Grade hold and cross-slope tuning (needs the IMU mounted and characterised)
- Payload weighing calibration (needs known loads)
- Self-level coupling table (needs the lift geometry settled)
- Decel pedal, boom down-pressure (trivial once the hardware exists)

---

## Two disciplines to hold

**1. The safety chain is not application software.** Everything in `src/st/` is
the functional layer. Drive-enable, PTO stop and operator-presence must be
removed by a path rated independently of this program. And the PTO adds a second
regulatory regime — a machine with a PTO is agricultural machinery as well as
earth-moving, so ISO 25119 may govern where ISO 13849 otherwise would. Scope it
before the safety chain is written. See `00` §2 and `05` §6.

**2. Protect the coherence.** This machine is good because its decisions
compound. The failure mode from here is feature accretion — each addition
individually reasonable, collectively turning a machine that is excellent at
three things into one that is mediocre at eight. When something new is proposed,
test it against the charter above: does it reinforce the other decisions, or
does it just add capability?

The three things this machine is for are **loading, pulling, and dozing**.
Anything that does not serve those is a candidate for deletion, not debate.

---

## Documents

| | |
|---|---|
| `00-architecture.md` | Control system architecture, signal inventory, execution model |
| `01-hardware-selection.md` | Controller, grips, valves, engine, bus layout |
| `02-operator-interface.md` | Axis assignment, button map, function behaviour |
| `03-sourcing-and-supply.md` | Purchase points, second sourcing, production ramp |
| `04-crossover-concept.md` | Crawler-loader heritage features, ranked |
| `05-rear-implement-architecture.md` | Hitch, PTO, engine orientation, regulatory |
| `06-frame-balance-and-stability.md` | Load cases, ballast strategy, load moment |
| `07-dozing-and-drawbar.md` | Capacity/pull trade, blade mounting, grade control |
| `08-dozer-attachment-integration.md` | Push link over-constraint, load-path modes |
| `09-engine-selection.md` | Cummins B4.5, the air-cooled blocker, cooling package |
| `10-cummins-supplier-questions.md` | Engine supplier call checklist, prioritised |
| `11-attachment-philosophy.md` | Power plant vs function, two-tier strategy, reservoir |
