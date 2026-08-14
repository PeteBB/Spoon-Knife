# Attachment Philosophy — Power Plant vs. Function

## 1. The organising idea

> "The loader needs to be smart, but smart at its everyday use. It needs to be
> the power plant, but the function of the attachment needs to be attachment
> driven."

This is the right architecture, and it is worth stating as a principle because
it decides a lot of downstream questions:

| The machine provides | The attachment provides |
|---|---|
| Flow, pressure, power | Its own valving |
| A flow rate limit and a pressure limit | Its own function logic |
| Direction and on/off | Its own operator interface for complex functions |
| Case drain return | Knowledge of what its functions mean |
| Everyday intelligence — traction, stability, grading, hitch, PTO | Everything specific to itself |

**The machine should not have to know how a tree shear works.** The moment it
does, you have signed up to design your machine around every attachment that
might ever exist — including ones invented after your machine ships.

### Why this matters more for you than for an incumbent

Bobcat can afford to integrate attachments deeply because they sell both and
they have thirty years of installed base. You do not have that, and copying it
would be the slowest possible path.

**Making the machine a clean, universal power plant is the faster and more
defensible position.** It means:

- A third party can build an attachment for your machine without your
  engineering involvement
- You are not the bottleneck on your own attachment catalogue
- Complexity lives with the person who understands it — the attachment designer
- Your control software stays about *loading, pulling and dozing*, which is the
  coherence discipline in the project charter

---

## 2. The interoperability complaint is the real market signal

> "When an operator hooks onto something he wants to put it to work, not fumble
> through wiring diagrams that only work on his brand of machine."

That is the whole problem with attachment electrics today. Every manufacturer
has a different connector with different pin functions, and an attachment built
for one machine does not plug into another. The customer eats the incompatibility.

Which leads to a two-tier strategy that is genuinely better than either tier
alone.

### Tier 1 — machine-integrated, over CAN

The attachment announces itself, loads its profile, remaps the grip buttons,
sets its own flow and pressure limits, and puts its own screen on the display.
Best possible experience. **Works only on your machine.**

This is the ecosystem play, and it is what makes an owner buy *your* attachments
rather than generic ones.

### Tier 2 — self-contained, works on anything

The attachment carries its own power, its own valving and its own control. It
needs nothing from the machine except flow and pressure. **Works on every
machine ever built, including your competitors'.**

This is the market-expansion play, and it is the one people underestimate:

> **You can sell Tier 2 attachments into the entire installed base of every
> brand.** At launch, your own machine population is zero. The addressable
> market for an attachment that works on anything is several hundred thousand
> machines on day one.

### The important part: the same attachment can do both

Fit the CAN connector *and* the self-contained control. On your machine it is
premium and integrated. On a rental Bobcat it still works. You get the
ecosystem lock-in without giving up the bigger market, and the customer never
gets punished for owning the wrong loader.

That is a genuinely strong product position and I have not seen anyone do it.

---

## 3. The M18 pendant concept

> A DC stack valve on the attachment, powered by a Milwaukee M18 pack,
> controlled by a remote pendant that talks to the attachment.

**The battery choice is the clever part**, and it is not a detail. M18 is
everywhere. Every contractor and every farm already owns packs and chargers.
That means:

- No proprietary battery to stock, warranty or supply
- No charger in the box
- The customer already owns spares, and already has a charging habit
- A dead pack is a five-second swap, not a service call

Choosing an existing ubiquitous ecosystem instead of inventing one is exactly
right, and it is the kind of decision that makes a product feel considered.

### The engineering that has to be done honestly

None of these kill the idea. All of them need designing rather than assuming.

| Issue | Reality | Approach |
|---|---|---|
| **Voltage** | M18 is ~18 V nominal, ~20 V fresh off the charger. Most mobile DC valve coils are 12 V. 18 V on a 12 V coil cooks it. | Buck converter, or specify coils rated for the range. Not hard, but it is a board, not a wire. |
| **Power budget** | A stack valve solenoid pulls roughly 1.5–2 A at 12 V. A 5 Ah M18 pack is ~90 Wh. | **Pull-in then PWM hold** — drop to ~30% current once the spool has shifted. This is the difference between one hour of runtime and most of a shift. Calculate it properly before committing. |
| **Heat** | Solenoids plus a converter in a sealed box, in the sun, on a machine. | Thermal design of the enclosure; PWM hold helps here too. |
| **Environmental** | M18 packs are not IP-rated for this world. | Sealed enclosure with a gasketed battery bay. The pack lives inside, not exposed. |
| **Cold** | Lithium packs lose capacity hard below freezing, and this is a cold-weather business. | Insulated bay; publish an honest cold-weather runtime figure rather than a room-temperature one. |
| **Theft** | A visible M18 pack on an attachment sitting in a field will walk. | Locking bay. Non-trivial — this is a real objection from rental fleets. |

### The one that is not just engineering — wireless safety

**A wireless pendant commanding hydraulic functions is a safety-relevant
control.** The requirements are well understood but they are not optional:

- **Loss of signal must fail to neutral**, immediately and always
- Continuous link supervision with a heartbeat, not just a command channel
- Defined timeout, and defined behaviour on timeout
- Unique pairing, so the pendant for one attachment cannot command another —
  on a site with three of your grapples, this is not hypothetical
- Emergency stop on the pendant that is a real stop

There are established standards for radio remote control of machinery. Get them
scoped alongside the ISO 25119 / ISO 13849 question already open in the project
charter. **This does not kill the idea — it is normal for the category — but it
is not a weekend project.**

### Where the pendant genuinely wins

Worth being clear about the real benefit, because it is not just convenience:
**the operator can be outside the cab.** Hooking up, positioning a grapple
around a log, setting a trencher on a line, spotting a shear on a stem — these
are all jobs where being at the attachment beats being in the seat. That is a
capability the in-cab joystick simply cannot offer, and it is worth more than
the interoperability argument.

---

## 4. The reservoir problem — a very good catch

> "One bad hose leak while sitting unattended and the machine goes 2–3 gallons
> low once reattached."

This is a real failure mode and it is the kind of thing only field experience
surfaces. The sequence is:

1. Attachment sits disconnected. Flat-face couplers seal the machine side, so
   the machine loses nothing — but the attachment bleeds its own trapped charge
   through a weeping hose or fitting.
2. Operator reconnects.
3. The attachment's motor, hoses and lines refill **from the machine's
   reservoir** — 2–3 gallons on a big high-flow head.
4. The machine is now low, and nobody knows until something is damaged.

### On the separate-reservoir remedy

The instinct is right but the specific fix has a problem: **an open-circuit
attachment cannot have its own isolated reservoir.** Oil supplied by the machine
has to return to the machine, so two reservoirs in one circuit fight each other
on level balance and aeration. It works only if the attachment carries its own
pump and runs a genuinely closed circuit — which is a much bigger, heavier,
more expensive attachment.

What actually solves it, in order of effectiveness:

1. **Size the machine reservoir with declared refill reserve.** Cheapest and
   most effective. Specify the tank so that filling the largest supported
   attachment still leaves you above minimum, and publish that number.
2. **Reservoir level sensing with temperature compensation** — see below. This
   is the controls answer and it is nearly free.
3. **Attachment fill volume in the attachment profile**, so the machine can warn
   *before* you connect something that will drop it below minimum.
4. **Coupler and cap discipline** — flat-face couplers, dust caps that actually
   seal, and storage guidance in the operator manual.

### What `FB_ReservoirGuard` does

**Temperature compensation first.** Hydraulic oil expands appreciably with
temperature. A level sensor reads meaningfully differently at 20 °C than at
80 °C, and an uncompensated low-level alarm will cry wolf every cold morning
until the operator learns to ignore it — at which point it is worse than useless.

**Staged response, and a deliberate asymmetry:**

| State | Response |
|---|---|
| **OK** | Nothing |
| **LOW** | Warn clearly, keep working |
| **CRITICAL** | **Inhibit aux and work hydraulics. Do NOT inhibit propel.** |

That last line is a judgement call worth stating plainly. Running a pump with
air ingestion destroys it, so cutting the high-flow consumer is right. But
stranding the machine in the middle of a field is also a real cost, and the
operator needs to be able to drive it onto the trailer. **Mobility is preserved,
at reduced speed, with the display shouting.** Same principle as never blocking
the lowering of a load: keep the action available that lets the operator resolve
the situation. Review the specific thresholds with your hydraulics supplier.

**Leak detection.** The block tracks level over a long window and computes a
loss rate. A slow leak that would otherwise be discovered as a seized pump
becomes a message on the screen a week earlier. Nothing in this class does this,
and it costs one sensor you should be fitting anyway.

**Pre-connect check.** If the attachment profile declares a fill volume, the
machine can say *"connecting this will put you below minimum — add oil first"*
instead of letting the operator find out afterwards. This is the direct answer
to the scenario you described.

---

## 5. What this means for the machine's aux circuit

Keep it deliberately simple and universal:

- Proportional flow, both directions
- Operator-set flow limit
- Pressure limit from the attachment profile, with a safe default for unknowns
- Case drain return, properly sized
- Detent for continuous running
- Electrical: **power and CAN on a standard connector** — and publish the pinout

That last point is the one that costs nothing and buys goodwill: **publish your
attachment interface.** An open, documented interface is how you get third
parties building for your machine instead of around it, and it is the exact
opposite of the wiring-diagram frustration that started this conversation.
