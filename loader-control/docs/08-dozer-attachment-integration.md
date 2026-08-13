# Dozer Attachment — Subframe Integration and Machine Modes

> **Scope note:** the kinematic analysis below is solid and it drives the
> control design. The actual slot geometry, wear pads, bushing selection and
> load paths need your mechanical engineer. I am reasoning about mechanism, not
> designing structure.

---

## 1. Your instinct is right, and the reason matters

Tying the blade back to a lower push point on the frame is the correct idea. It
takes horizontal thrust out of the loader arms and puts it into the frame, which
directly solves the torsion problem flagged in `07-dozing-and-drawbar.md` §3 —
the most likely way to break a machine that otherwise works.

But it creates a new problem, and you spotted it: **the linkage becomes
over-constrained.**

The loader arms swing through an arc. The lower push point is fixed to the
frame. If the blade subframe is rigidly pinned to both, then raising the arms
tries to move the upper connection along its arc while the lower connection
cannot move at all. The geometry does not close. **Something has to yield, and
it will be whichever component is weakest** — the push link, its frame mount, or
the quick-attach plate.

That is a statically indeterminate mechanism, and it is why your question about
a vertical stop is exactly the right question.

---

## 2. The principle that decides the answer

You proposed solving it with a PLC mode — limit arm travel in software when the
dozer is fitted. That instinct is understandable and **I think it is the wrong
place for the constraint.**

A software-only limit means the application program is now **load-bearing for a
structural constraint.** Every one of these tears the machine apart:

- attachment ID node fails or the connector is dirty → dozer not detected
- boom angle sensor drifts or fails → limit computed against a wrong angle
- a machine gets an older firmware at a dealer → limit absent
- someone builds a third-party blade that does not announce itself

This is the same principle as the safety chain in `00-architecture.md` §2. **A
structural limit protected only by application software is a structural limit
that will eventually fail**, and it will fail expensively and out of warranty.

The rule to design to:

> **Exceeding the limit must degrade performance, not break hardware.**
> Software optimises within the mechanism's envelope. The mechanism enforces
> the envelope.

---

## 3. Four ways to resolve the over-constraint

| | Approach | Verdict |
|---|---|---|
| **A** | Software arm-travel limit, rigid link both ends | **No.** Software is load-bearing for structure. |
| **B** | **Slotted / sliding lower push point** | **Recommended.** |
| **C** | Operator-pinned lower link at a set arm height | Workable, but a manual step people forget |
| **D** | Break-away or spring-loaded link | Complexity for no real gain |

### Why B — the slotted push point

The lower connection becomes a **slot or sliding trunnion**: it transmits
horizontal thrust into the frame while permitting vertical travel. The arms move
through their arc, the subframe's lower pin slides in the slot, and nothing
binds.

The elegance is in what happens at the top of the slot: **the pin simply runs
out and disengages.** No bind, no yield, no damage. You lose push assist and
nothing else. The failure mode of exceeding the envelope is *the blade stops
pushing hard*, which is exactly the "degrade, do not break" behaviour we want.

That reduces the software from a structural protection to an **optimisation** —
which is where software belongs.

Design notes for your mechanical engineer: the slot must run out *before*
anything else reaches a hard stop; it needs replaceable wear pads because it
will see high thrust with contamination; and there should still be a mechanical
backstop on arm travel as a last line, independent of the slot.

---

## 4. "Or make the front loader an attachment itself?"

This is a better idea than it first sounds, and it is worth doing **as well**,
not instead.

Here is the thing: **tractor front loaders are already removable.** A Kubota
LA-series or Deere H-series parks on its own stands and the tractor drives away
in about five minutes. CTL loaders are integral and never come off. **You are
building a tractor.** Designing the loader as a tractor-style quick-detach unit
is consistent with everything else you have chosen.

| | Slotted push link (§3B) | Loader-off, dozer on frame mounts |
|---|---|---|
| Swap time | Seconds — like any attachment | Minutes, with stands |
| Structural ideal | Very good | **Perfect** — true dozer geometry |
| Arm rigidity penalty | None | None |
| Customer will actually use it | **Yes** | Only for multi-day dozer work |

**Recommendation: do both.**

- **Slotted push link** is the default path. The blade goes on like any other
  attachment, the customer uses it because it costs them nothing, and thrust
  goes into the frame.
- **Design the loader as quick-detach from the start** — tractor-style, parking
  stands, quick-couplers. That is correct for the ag positioning regardless, and
  it gives you the option of a dedicated frame-mount dozer configuration later
  for land-clearing customers without redesigning anything.

The mounting interface on the frame serves both. Design it once.

---

## 5. The control modes this creates — the genuinely interesting part

The slot resolves the structure. What the controller adds is knowing **which
load path is active** and behaving accordingly.

### Three push regimes

| Regime | Arms | Thrust path | Rimpull allowed |
|---|---|---|---|
| **FRAME** | Low, pin in the slot | Frame — the strong path | **Full** |
| **TRANSITION** | Near slot top | Handing over | Fading |
| **ARMS** | Above slot, pin disengaged | Loader arms — the weak path | **Limited** |

This is the feature. **The rimpull ceiling becomes a function of boom height
when the dozer is fitted.**

The operator can still raise the blade — over a windrow, over an obstacle, to
back-drag at height — and the machine simply will not push hard while it is up
there. Nothing is forbidden; the structure is protected by the machine declining
to generate force the arms cannot carry.

That is a far better answer than blocking lift, because it never takes away a
motion the operator needs, and because it protects the arms in the case that
matters — high *force*, not high *position*.

And it reuses machinery already built: `FB_TractiveControl` already caps rimpull
on an input. `FB_DozerMode` just schedules that input against boom angle.

### Fail restrictive, not fail permissive

If the dozer is detected but its profile fails to load, or the boom angle sensor
is implausible, or the push-link sensor disagrees with the boom angle, the
controller assumes **the weak load path** — full arm limiting and derated
rimpull.

A machine that quietly reverts to full push force when a sensor drops out is a
machine that breaks itself. **Doubt resolves toward the conservative
configuration**, always. The operator sees a message explaining the reduced
performance rather than discovering it as a bent arm.

### Sensing the link state

Add a **proximity or position sensor on the push link.** It is cheap, and it
lets the controller cross-check the geometric inference (boom angle says the pin
should be engaged) against physical reality (it is, or it isn't). Disagreement
means something is bent, worn, or mis-installed — which is exactly the condition
you want reported before it becomes a failure.

---

## 6. Other mode changes when the dozer is fitted

| Function | Change |
|---|---|
| Self-level | **Disabled.** Meaningless with a blade; the coupling constant does not apply. |
| Return-to-dig / carry | Repurposed as **blade depth teach and recall** |
| Cross-slope hold | **Enabled** (`FB_BladeControl`) |
| Blade load control | **Enabled** (`FB_BladeControl`) |
| Load moment indicator | Relaxed — a blade on a push link is not a tipping load in the same way |
| Steering priority | Bias toward **crawler** (`FB_DriveMixer`) — dozing wants forward thrust preserved through corrections |
| Float | Available, and more useful than in loader mode |
| Height limit | Set to the slot-top angle by default, operator-adjustable above it |

All of these load from the attachment profile, which is what the configurable
binding system in `02-operator-interface.md` was built for. Plug in the dozer
and the machine reconfigures itself — including the button map, so the operator
gets blade angle and pitch on the grips instead of aux flow.

---

## 7. What this needs from the mechanical side

- Slot geometry, travel, and the arm angle at which the pin disengages — this
  number is the single input `FB_DozerMode` needs, and everything else follows
- Replaceable wear pads in the slot
- An independent mechanical backstop on arm travel
- Frame mounting interface sized for both the push link and, later, a
  frame-mount dozer C-frame
- Thrust load path from the push point into the track frames, not just the
  chassis skin
- Push link sensor mounting, protected from the debris a dozer generates
