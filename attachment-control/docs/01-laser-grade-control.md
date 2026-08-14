# Laser Grade Control — Components and Control Approach

## 1. Why this works, in one idea

A rotating laser on a tripod sweeps a **plane of light** across the site. A
receiver on a mast tells you where it sits relative to that plane. That is the
entire principle, and it has run grading work for forty years.

The part that makes it powerful is the bit people miss:

> **The laser plane IS the design surface.** Tilt the laser to the grade you
> want, and a receiver simply holding "on grade" produces that grade
> automatically — in every direction, across the whole site, with no cross-slope
> control at all.

You are not measuring a slope and correcting for it. You are following a
physical surface made of light that already *is* the answer.

## 2. Why it fits this product perfectly

Automatic grade control has to move the cutting edge. On a loader, lift is a
*machine* function — which would break the whole "never touch the machine"
architecture.

**Unless the attachment moves its own cutting edge.** And grading attachments
do: a box blade, land plane or grader attachment with its own hydraulic height
cylinders, riding on skids or wheels, with the machine simply driving forward.

That is a real and established product category, and it means:

```
   LASER TRIPOD ──light──► RECEIVER ──► M18 MODULE ──► ATTACHMENT'S OWN CYLINDER
                          (on mast)     (the brain)      (moves the cutting edge)

   MACHINE: drives forward. Supplies flow. Knows nothing. Never modified.
```

**Zero machine integration. Works on any loader. Exactly the thesis.**

## 3. The little-guy argument is real

| | GPS machine control | Laser |
|---|---|---|
| System cost | Tens of thousands | **Low thousands, or hundreds used** |
| Base station / corrections | Required, often a subscription | **None** |
| Cellular dependency | Usually | **None** |
| Vertical accuracy | Centimetre-class with RTK | **Millimetre-class** |
| Complexity to operate | Training, site files, design surfaces | **Set the tripod, set the grade, drive** |
| Complex 3D surfaces | Yes | No — planes only |

For pads, driveways, building sites, parking areas, arena floors, drainage falls
— which is nearly all of what a small contractor actually grades — **laser is
not the poor man's version. It is the correct tool**, and it is more accurate
vertically than GPS.

Where GPS wins is complex 3D design surfaces and knowing *where you are* on the
site. If the job is "make this flat, or make it fall 2% to the drain," laser is
better, simpler and an order of magnitude cheaper.

---

## 4. Component list

### A. Rotating laser transmitter — on the tripod

Establishes the reference plane. Specify:

- **Self-levelling**, and it should shut down or alarm if knocked out of level.
  A laser quietly grading to a wrong plane is the one genuinely expensive
  failure mode in this whole system.
- **Single-grade or dual-grade** capable — this is what lets you dial in a fall
  rather than only working level. Dual-grade sets slope on two axes.
- Working radius to suit your sites (a few hundred metres with a receiver is
  typical).
- Rugged, and it will get knocked over eventually.

Used construction lasers are plentiful and cheap. This is not the part to buy
new first.

### B. Laser receiver — on a mast on the attachment

The sensor. Two grades of them, and the difference matters:

| | Simple receiver | **Machine-control receiver** |
|---|---|---|
| Output | LEDs, buzzer — for a person holding a grade rod | **Electrical signal: above / on / below, often with proportional offset** |
| Use here | Indicate only | **Automatic control** |

**You need the second kind.** Look specifically for one sold for *machine
control* with a control output — many have a simple digital or serial interface
designed for exactly this job, because dozer and box-blade systems have used
them for decades.

A **proportional output** (actual millimetres off plane, not just high/low) is
worth paying for. It turns the control loop from crude bang-bang into something
smooth, as §6 explains.

### C. The mast

Boring, and it decides your accuracy. Needs to be:

- **Rigid** — mast flex is measurement error, directly
- **Adjustable and repeatable**, with a recorded reference height
- **Breakaway or spring-mounted** — it will meet a tree branch
- Tall enough to see over the load and the attachment

### D. The attachment's own height cylinder

What actually moves the cutting edge. Must be on a **spring-centred valve** —
the same hard requirement as everything else in this product. Power lost, laser
lost, module dead: the cylinder stops and holds.

### E. The M18 module

Reads the receiver, runs the loop in `firmware/laser_grade.c`, drives the valve.
No new hardware — it is the module you are already building, doing one more job.

### F. Optional: an IMU

Two uses:

1. **Cross-slope hold** when you cannot see the laser, or on a second axis
2. **Damping** — the machine pitches as it drives, and the IMU lets the loop
   distinguish "the blade moved" from "the whole machine rocked"

Cheap, and worth adding once the basic loop works.

---

## 5. What it cannot do — be straight with customers about this

- **Line of sight is required.** Trees, spoil piles, buildings, the machine's
  own boom. Lose the beam, lose control — and the logic must handle that
  gracefully rather than dangerously.
- **Planes only.** Compound surfaces, curved crowns and complex 3D designs are
  GPS territory.
- **It knows height, not position.** The system has no idea where it is on the
  site — only how far it is above or below the plane.
- **Setup discipline matters.** A wrongly set mast reference or a bumped tripod
  produces confidently wrong grade. Build the checks in §7 to catch it.

---

## 6. The control approach — and why the obvious loop fails

### Do not run a continuous closed loop

The instinct is to sample the error and continuously drive the valve
proportionally. **That oscillates**, badly, because there are three lags in
series:

1. **Valve and hydraulic response** — spool shift, flow, cylinder movement
2. **Mechanical lag** — the attachment settling on its skids
3. **Measurement lag** — the receiver reading takes time to stabilise as
   everything moves

By the time the reading reflects your correction, you have already applied three
more. The blade hunts up and down and the finish looks worse than manual.

### Pulse and settle

The approach that works, and the one every good laser system uses:

```
   measure → outside deadband? → fire a PULSE proportional to the error
                                        │
                                        ▼
                              WAIT for it to settle
                                        │
                                        ▼
                                  measure again
```

Each cycle is one deliberate nudge, then a pause long enough for the hydraulics
and the machine to actually respond. Slower in theory; **dramatically better
finish in practice**, because it never fights its own last correction.

### Pulse width proportional to error

With a simple on/off valve you can only go up, down or stop. But you control
*how long*:

| Error | Response |
|---|---|
| Inside deadband | Nothing |
| Slightly off | Short pulse — a nudge |
| Well off | Long pulse |
| Far off | Continuous drive until it comes back into range |

That gives you effectively proportional behaviour from on/off hardware — which
is exactly what the module already has, since it drives selector solenoids.

### Deadband is a feature, not a compromise

Without an on-grade band the valve chatters continuously, wears itself out and
leaves ripples. **The deadband should be operator-adjustable** — tight for
finish work, wide for rough cut. This is the single control the operator will
actually reach for, so put it on the pendant, not in a menu.

---

## 7. Failure handling — the part that earns trust

| Condition | Response |
|---|---|
| **Laser signal lost** | Stop correcting immediately. Hold position. Tell the operator. **Never drive the cylinder blind** — that is how you gouge a finished pad. |
| **Signal returns** | Require a brief period of *stable* signal before resuming, so a flicker through a branch does not produce a jerk. |
| **Operator touches the control** | Yield instantly. Resume only after they release *and* the reading is stable again. The operator always wins — auto grade that fights the hand on the control is auto grade that gets switched off permanently. |
| **Correcting a long time with no improvement** | The cylinder is at end of stroke, or the attachment physically cannot reach grade. Stop, alarm. This gives end-of-stroke detection with no position sensor. |
| **Error implausibly large on first acquisition** | Do not lunge. Require the operator to get roughly on grade manually first, then engage. |

That fourth row matters more than it looks: it is free diagnostics. A system
that says *"I have been asking for down for eight seconds and nothing is
happening"* catches a stuck valve, a failed coil, a blade already buried, and an
attachment that has run out of travel — all with logic you were writing anyway.

---

## 7a. Implementation

`firmware/laser_grade.c` — MCU-agnostic, same `lg_hal_*` split as the safety
core, compiles clean under `-Wall -Wextra`.

| State | Meaning |
|---|---|
| `LG_NO_SIGNAL` | Beam lost — cylinder stopped, operator told |
| `LG_ACQUIRE` | Signal good but error too large; operator must get roughly on grade first |
| `LG_ON_GRADE` | Inside the deadband, valve centred |
| `LG_PULSE` | Correction pulse running, width sized to error |
| `LG_SETTLE` | Waiting for the machine to actually respond |
| `LG_YIELD` | Operator is driving it manually |
| `LG_FAULT_STUCK` | Repeated corrections with no improvement |

---

## 8. Where this sits in the roadmap

Still **v2**, after functions 2/3/4 ship. But it is now a much more concrete v2
than "GPS grade someday", it needs no subscription or base station, and it uses
the same module, the same drivers and the same safety core.

The upgrade path for a customer is: buy the module for attachment functions,
then add a receiver and a used laser when they want grade. **Same box. Nothing
thrown away.** That is a good story on a dealer floor and a good reason to buy
the module first.
