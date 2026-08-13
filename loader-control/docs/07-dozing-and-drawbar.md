# Repositioning: Dozing and Drawbar Machine

## 1. Why trading lift capacity for pull is the right trade

The two capabilities want the machine's mass to do **different jobs**:

| | Loader capacity wants mass as… | Drawbar and dozing want mass as… |
|---|---|---|
| Role | **Counterweight** — dead, reactive | **Traction** — working, productive |
| Position | Far rear, behind the tracks | Over the contact patch, low and centred |
| Effect of adding more | Resists tipping. Does nothing else. | Directly increases pull and push |
| Effect on pushing | **Hurts** — worsens pitch-back | **Helps** |

Reducing lift capacity does not really make the machine lighter. **It lets the
same mass stop counterbalancing and start working.** Weight moves out of the
tail and into the belly and over the tracks, and almost everything improves at
once: lower CG, more drawbar pull, better push, less pitch-back, better
grading stability, cheaper frame.

This is a better machine, not a compromised one.

### It also recovers the market I said you were losing

At 5,000 lb ROC I put operating weight at 15,000–18,000 lb and warned that the
combination crossed the CDL threshold. Backing capacity off to **~3,000–3,500
lb ROC** puts operating weight around **11,000–13,000 lb**:

> 13,000 lb machine + ~3,000 lb trailer + ~8,000 lb truck ≈ 24,000 lb — back
> under the 26,001 lb threshold.

So the scattered-site contractor comes back into range, and the ag buyer never
left. **You get both markets back.** Verify the licensing rules for your target
states rather than taking that from me, but the direction is clear.

---

## 2. The numbers hang together

At roughly 12,000–13,000 lb on rubber tracks with a traction coefficient around
0.7–0.9 on soil:

- **Drawbar pull ≈ 9,000–11,000 lbf**, traction-limited

Check that against the engine: 100 hp is 55,000 ft·lb/s. At 10,000 lbf, that is
5.5 ft/s ≈ **3.75 mph** — a sensible tillage and dozing speed.

**Power and traction are well matched at this weight.** You are not carrying
engine you cannot use, and you are not carrying weight the engine cannot pull.
That is the sign of a coherent design point, and it is worth noting how rare it
is — most machines are badly mismatched in one direction or the other.

For comparison, a wheeled 100 hp tractor at similar weight gets meaningfully
less drawbar pull because wheels slip where tracks grip. **That gap is the
entire product argument**, and it gets stronger in exactly the conditions your
buyers work in — wet, soft, sloped.

**If drawbar pull turns out to be the binding constraint, the answer is ballast,
not a bigger frame** — and the three-point hitch ballast system from
`06-frame-balance-and-stability.md` §3 already covers it. Hang weight on for
tillage, strip it for transport.

---

## 3. The dozer blade: mount it on the loader arms

Two ways to hang a blade, and the obvious-looking one is wrong for you:

| | **Quick-attach blade on the loader arms** | Dedicated C-frame / push beam |
|---|---|---|
| Grading precision | Lower — arm compliance | **Higher** — loads into the track frames |
| Attachment ecosystem | **Preserved** | Broken — this is a second front end |
| Cost | Blade only | Blade + frame + a machine that is no longer a loader |
| Precision gap | **Closable in software** | — |

**Go quick-attach.** Crawler loaders dozed perfectly well with the tool on the
arms, the attachment ecosystem is most of your value proposition, and the
precision gap is closable with cross-slope hold, float and blade load control —
which is software you are building anyway.

### Two structural requirements this creates

1. **Spec the arms and pins for push and lateral loads, not just lift loads.**
   These are different load cases. Angle dozing puts sustained **torsion** into
   the loader arms that a purely lift-rated arm will not survive. This is the
   single most likely way to break a machine that otherwise works.
2. **A 6-way blade needs three more hydraulic functions** — angle, tilt, pitch —
   beyond lift and tilt. The current plan has one proportional aux and one
   on/off. That is not enough. Add PVG sections now; they are cheap at design
   time and a re-plumb later.

---

## 4. The pattern that keeps recurring

Something worth noticing, because it is now the third instance:

| Where | Sensed | Response |
|---|---|---|
| Drivetrain | Propel pressure / slip | Cap rimpull (`FB_TractiveControl`) |
| Rear hitch | Draft force / slip | Raise the implement (`FB_HitchControl`) |
| Front blade | Propel pressure / slip | Raise the blade (`FB_BladeControl`) |

**All three are the same control problem: manage tractive load to prevent
slip.** They differ only in which actuator does the work.

That is worth stating explicitly because it means the machine has *three
coordinated levers* on traction where a competitor has zero or one, and because
the tuning intuition transfers — get one right and the other two follow. The
ordering matters too: lift the tool first (cheap, keeps working), cap rimpull
second (blunt, stops progress).

---

## 5. Dozing feature set

Built in `FB_BladeControl`:

- **Cross-slope hold.** Blade holds a commanded cross-slope regardless of
  machine roll, using the IMU already fitted for slip control. This is 2D grade
  control, and it is the feature that makes a novice operator produce a flat
  pad. Nothing in this class has it.
- **Blade load control / auto-carry.** Blade lifts slightly when propel load
  spikes, so the machine carries a full blade at a steady load instead of
  stalling and backing out. Fast rise, slow decay, exactly as the hitch draft
  loop does, and for the same reason — snapping the blade back down just
  re-buries it.
- **Float integration**, for back-dragging and finish passes.
- **Operator always wins** — any stick input on an axis drops the assist on that
  axis instantly, and it does not resume by itself.

Worth building later, gated on a real machine:

- **Slot dozing assistance** — hold the blade in the previous cut
- **Blade depth memory** — teach and recall a cutting depth
- **3D grade control interface** — a CAN interface for Trimble/Topcon rather
  than your own GNSS stack. Partner, do not build.

---

## 6. What changes in the existing documents

| Document | Change |
|---|---|
| `06-frame-balance-and-stability.md` | ROC target drops to ~3,000–3,500 lb; operating weight ~11,000–13,000 lb; CDL conflict largely resolves |
| `FB_LoadMoment.st` | `C_RATED_LB` and `C_MACHINE_LB` revised down |
| `01-hardware-selection.md` | Engine sizing unchanged — the HP is for PTO and drawbar, and that argument is unaffected |
| Aux hydraulics | **Needs expanding** — three more proportional sections for a 6-way blade |

The engine decision is the one thing that does **not** move. You are keeping the
horsepower for PTO and pull, which was always the reason for it. Reducing lift
capacity never touched that argument.
