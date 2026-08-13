# Frame Concept, Balance and Stability

**Boundary note up front:** frame structure is not something I can finish for
you. Section loads, weldment design and FEA need a mechanical engineer and a
model. What follows is the load-case analysis, the balance targets, the design
levers and — the part that is mine — the control features that fall out of a
machine this heavy carrying this much.

---

## 1. The number that reorganises the project

You said 4,000–5,000 lb pick-and-carry. Follow that through.

Rated operating capacity on this class of machine is a fraction of static
tipping load — the fraction depends on which standard applies, and it is worth
confirming which governs a machine that is arguably both earth-moving and
agricultural:

| ROC target | If rated at 35% of tipping | If rated at 50% of tipping |
|---|---|---|
| 4,000 lb | 11,400 lb tipping load | 8,000 lb tipping load |
| **5,000 lb** | **14,300 lb tipping load** | 10,000 lb tipping load |

Operating weight on CTLs runs roughly 2.5–3.5× ROC. At 5,000 lb rated, you are
looking at a **15,000–18,000 lb machine**. For scale, the largest CTLs on the
market — Bobcat T870, Cat 299D3, ASV RT-135 — sit around 11,000–12,000 lb
operating weight with rated capacities in the 3,300–4,100 lb range.

**This machine is bigger than the biggest CTL made.** That is a legitimate
place to be. It just needs to be a decision rather than a surprise.

### The conflict with what I told you earlier

In `04-crossover-concept.md` I argued hard for staying under ~10,000 lb so the
machine trailers behind a pickup, and called that the class's biggest practical
advantage. **A 5,000 lb ROC machine cannot do that.** I am flagging the
contradiction rather than quietly dropping it.

Rough combination: 16,000 lb machine + ~3,000 lb trailer + ~8,000 lb truck is
around 27,000 lb combined. That crosses the 26,001 lb threshold that generally
triggers a Class A CDL for commercial operation. Farm exemptions exist in most
states for producers hauling their own equipment within a radius, and the rules
vary by state and by commercial-versus-farm use — **verify this for your target
markets, it is not something to take from me.**

Here is why I think you should accept the weight anyway: **it lands exactly
where your positioning already went.** You chose the ag-leaning machine when you
killed the mid-mount deck. A farm hauling its own equipment on its own gooseneck
is largely unbothered by all of the above. The buyer who gets squeezed out is
the contractor running scattered sites — and that buyer was already the weaker
fit for a tracked machine that does not like pavement.

So the honest framing: **the 5,000 lb target and the ag positioning are
consistent with each other, and both are inconsistent with the
contractor-mobility argument.** Pick two, and you have already picked which two.
The thing not to do is chase all three and build a machine that is mediocre at
each.

---

## 2. Three load cases that want opposite machines

| Case | Wants | Fights |
|---|---|---|
| **Pick and carry, 5,000 lb** | CG far rearward for counterbalance; long track contact for fore-aft stability | Pushing |
| **Pulling implements** (draft, drawbar) | Weight over the contact patch; long ground contact; rear bias helps | Tight manoeuvring |
| **Pushing / dozing** | CG forward and low; resists pitch-back | Carrying |

The pushing case is the one people get wrong. Driving a bucket into a pile
applies a rearward force at the cutting edge, above the ground line, against a
tractive force at the ground. That pair is a couple that **pitches the machine
nose-up** — it is why loaders wheelie into a pile. Rear ballast makes it worse.

So counterweight that helps you carry actively hurts you push. There is no
static distribution that is optimal for all three, which is why the answer is
not a number — it is a *reconfigurable* machine.

---

## 3. The elegant part: the three-point hitch IS your ballast system

You already added the thing that resolves the conflict.

Ag has solved reconfigurable ballast for a century: **suitcase weights on the
hitch.** Your customers already own them, already understand them, and already
expect to move them by task.

- Heavy loader and truck-loading work → hang weights on the three-point
- Drawbar and tillage work → the implement itself is the ballast, and its draft
  load transfers weight rearward for free
- Pushing and grading → strip the rear, run light

That turns a design conflict into an operator choice, at essentially zero
engineering cost, using hardware that is already on the machine. It is also a
genuine story on a spec sheet: *ballast-configurable by task*.

**And it gives the control system something to work with.** The hitch link
sensors specced in `05-rear-implement-architecture.md` can weigh whatever is
hanging on them — lift the implement, measure the load, and the controller
*knows* its current ballast state. That feeds directly into section 6.

---

## 4. Design levers, ranked

1. **Track ground contact length.** The dominant lever for fore-aft stability,
   ground pressure and grading quality. Go long. The cost is steering scrub on a
   skid-steer turn — which is precisely what the crawler steering mode in
   `FB_DriveMixer` mitigates, since it prefers effort-preserving turns over hard
   counter-rotation. **Long GCL and the crawler steering mode are synergistic;
   neither is as good without the other.**
2. **Engine position and orientation.** Already longitudinal. Put it as low and
   as far rear as PTO packaging allows — it is your single largest movable mass
   and it is working as counterweight for free.
3. **Tank placement.** Fuel and hydraulic oil are hundreds of pounds. In the
   frame rails, low, rear-biased. Never up high for packaging convenience.
4. **Track gauge.** Lateral stability, and it matters more than people expect
   once you are carrying 5,000 lb with the bucket offset or working a side-hill.
5. **Reconfigurable rear ballast** — section 3.
6. **CG height.** Everything heavy as low as it will go. On a side-hill with a
   raised load, CG height is the whole game.

---

## 5. Lift geometry — and a control consequence

**For 4–5,000 lb pick-and-carry and truck loading, go vertical lift.** It keeps
the load closer to the machine through the lift arc, which directly improves
tipping load at height — exactly the case you are designing for. Radial lift is
better for digging at or below grade and for mid-height reach, and it is
simpler, but it puts the load further out precisely where you are most
stability-limited.

**Control consequence, and it is a real one:** `FB_LoaderControl` currently
carries `C_COUPLING = -0.92`, a single constant describing degrees of apparent
bucket rotation per degree of boom rotation. That constant is a reasonable
approximation for radial lift. **On a vertical-lift linkage it is not constant
across the arc**, and self-levelling accuracy will visibly drift at the extremes
if it is left as a scalar.

The fix is a lookup table indexed on boom angle, populated by sweeping the boom
with the tilt cylinder locked and recording both sensors. That is an hour of
work on a real machine, and I flagged it in the block's header comment when I
wrote it. Say the word once the lift geometry is settled and I will convert the
constant to an interpolated table.

---

## 6. What this hands the control system: a load moment indicator

A machine rated at 5,000 lb has enough capacity to tip itself, and unlike a
telehandler nobody in this class ships a load moment indicator. That is an
opening.

`FB_LoadMoment` (built, see `src/st/`) computes, every 50 ms:

- **Payload weight** from lift cylinder pressure and boom angle
- **Overturning moment** about the front tipping fulcrum, from payload and boom
  geometry
- **Restoring moment** from machine weight, measured rear ballast, and IMU pitch
  — because a nose-down slope shortens the restoring arm and every static
  stability number on the spec sheet quietly assumes level ground
- **Stability margin** as a single percentage, with staged warning, then a
  progressive limit on boom raise as the margin closes

The IMU and the pressure sensors are already on the machine for slip control,
rimpull limiting and payload weighing. **The load moment indicator is nearly
free** — it is arithmetic on sensors you are already fitting, and it is a
safety story, a spec-sheet line and a liability position all at once.

The staged behaviour matters more than the maths. A machine that simply cuts out
at the limit is a machine operators disable. Warn early, warn clearly, degrade
progressively, and never take away the ability to *lower* the load — the one
control that always makes the situation better.

---

## 7. Starting balance targets

Treat these as the opening position for the mechanical design, to be validated
by a real weight study — not as answers.

| Condition | Front / rear | Note |
|---|---|---|
| Empty, no rear implement | ~40 / 60 | Rear bias for loader counterbalance |
| Rated load, carry position | ~55 / 45 | Still comfortably behind the fulcrum |
| Rated load, full height | Stability margin per standard | The governing case |
| Rear implement fitted, no load | ~35 / 65 | Implement acting as ballast |
| Pushing, no rear ballast | ~50 / 50 | Resists pitch-back |

The spread between rows one and four is exactly the range the reconfigurable
rear ballast is there to cover.

---

## 8. Undercarriage: one open decision

**Rigid vs. suspended/oscillating** is a genuine fork and I do not think it is
obvious:

- **Rigid** — better grading precision, simpler, cheaper, more predictable for
  the grade-hold feature. Harsher ride, worse ground contact on uneven terrain.
- **Suspended** (the ASV approach) — markedly better traction on rough ground,
  better ride, more consistent contact patch, which matters for a machine doing
  draft work. More complex, more cost, more to maintain, and it degrades grading
  precision.

For a machine doing both draft work and finish grading, I lean **rigid or
lightly oscillating**, because draft work rewards consistent, predictable ground
engagement and because the grade-hold and cross-slope features in
`04-crossover-concept.md` are easier to make trustworthy on a rigid platform.
But this one deserves a real conversation with your undercarriage supplier
before it gets locked.

---

## 9. What I need from a mechanical engineer, not from me

- Frame section loads for all three load cases plus the shock cases
- Weldment design and FEA
- Actual CG study once the major masses are placed
- ROPS/FOPS structure and certification
- Track frame attachment and load paths under draft
- Confirmation of which rating standard governs, since that sets the ROC number
  you are allowed to print

I can take the outputs of any of that and turn them into the calibration
constants the control blocks need.
