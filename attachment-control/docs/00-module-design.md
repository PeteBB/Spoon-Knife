# Module Design — System Map

## 0. Scope: the module adds functions 2, 3, 4 — it does not replace function 1

**This is the most important decision in the product, and it makes it better in
five ways at once.**

The attachment's *primary* function — open/close on a grapple, in/out on a
shear — stays on the machine's own auxiliary rocker, exactly as it works today.
The module supplies the **secondary** functions: rotate, tilt, clamp, whatever
the attachment adds beyond the basics.

```
   MACHINE AUX  ──►  DIVERTER / STACK  ──┬──► FUNCTION 1  (machine rocker)
   flow + direction         ▲            ├──► FUNCTION 2  ┐
   + PROPORTIONAL           │            ├──► FUNCTION 3  ├─ module selects
                            │            └──► FUNCTION 4  ┘
                     module selects which
```

### Why this is better than the module driving everything

1. **Every function gets proportional control for free.** The machine's rocker
   is still doing the modulating — the module only *selects where the flow
   goes*. Feathering a rotate is suddenly as good as feathering the grapple,
   which is something the competitor products cannot offer at all.
2. **The module becomes a selector, not a controller.** On/off solenoids only.
   No proportional drivers, no current-control loops, cheaper BOM, simpler
   firmware.
3. **Lower power draw**, because selection solenoids are energised briefly and
   in fewer combinations than modulating coils would be.
4. **Nothing existing is disturbed.** The primary function's plumbing and
   controls are untouched, which makes installation far less intimidating.
5. **It is a much easier sell.** "Keep everything you have and add three
   functions" beats "replace how your attachment is controlled."

### The trade-off, stated plainly

Selection means **one function at a time** — you cannot rotate and clamp
simultaneously. For nearly every attachment in this class that is exactly how
they already work, so it costs nothing real. Note it in the manual and move on.

### What this means for the hardware

The module's outputs drive **diverter and selector solenoids**, not modulating
coils. Channel count drops, drivers get simpler, and the peak-and-hold strategy
matters even more — a selection solenoid may sit energised for the whole time
an operator is using function 3.

---

## 1. Two units, one job

| | **Attachment module** | **Joystick clip** |
|---|---|---|
| Mounts | On the attachment, next to its valve | Clamps to the machine's existing grip |
| Power | M18 pack | Coin cell or small rechargeable |
| Job | Receive commands, drive solenoids | Read buttons, transmit |
| Environment | Brutal — impact, dust, wash-down, sun | Sheltered, in the cab |
| Target life | Multi-day per pack | A full season per cell |

A handheld pendant is a **third unit for later**, sharing the same radio
protocol and pairing. Do not build it first — the clip is the differentiator.

---

## 2. Attachment module — block diagram

```
   M18 PACK
      │  18 V nominal (20 V fresh, ~15 V flat)
      ▼
  ┌──────────────┐
  │ Pack contacts│  reverse-polarity + inrush protection
  └──────┬───────┘
         ├──────────────► BUCK 18→12 V ──► solenoid rail
         │                                     │
         └──► LDO/buck 3.3 V ──► MCU ──────────┤
                                  │            │
                                  │       ┌────▼──────────────┐
                              RADIO RX    │ 4–6 low-side      │
                              (915 MHz)   │ drivers, each     │
                                  │       │ with current      │
                              ANTENNA     │ sense + PWM hold  │
                                          └────┬──────────────┘
                                               ▼
                                       Deutsch DT connector
                                       to the attachment valve
```

**Low-side drive** rather than high-side: cheaper, simpler, and hydraulic
solenoid coils are almost always supplied as an isolated pair. Add current sense
per channel — it gives you open-coil and short detection nearly free, which is
the difference between "it doesn't work" and "channel 3 coil is open."

---

## 3. Power budget — the numbers work, and here is why

M18 pack energy:

| Pack | Energy |
|---|---|
| 5.0 Ah XC | 18 V × 5.0 Ah ≈ **90 Wh** |
| 12.0 Ah HD | ≈ **216 Wh** |

A typical 12 V hydraulic cartridge solenoid draws around **20 W** (≈1.7 A).

### Peak-and-hold is worth roughly 3× the runtime

A solenoid needs full current only to *shift* the spool — perhaps 80–150 ms.
Holding it shifted takes far less. Drive full current to pull in, then PWM down
to roughly 35 % duty:

| Strategy | Power while energised | 5.0 Ah pack, coil held continuously |
|---|---|---|
| Full current | 20 W | **~4.5 hours** |
| **Peak-and-hold** | ~7 W | **~13 hours** |

### Realistic duty cycle

Real attachment coils are not energised continuously. A grapple's coils are live
maybe 15 % of working time:

> 7 W × 0.15 duty ≈ **1 W average** → a 5.0 Ah pack runs **multiple days** of
> normal grapple work.

MCU and radio in continuous receive are around 20 mA at 3.3 V — about 66 mW, or
half a watt-hour across a shift. **Irrelevant next to the coils.** Do not
over-engineer sleep modes; spend the effort on peak-and-hold instead.

> **Verify against your actual coils.** Some cartridge valves need more hold
> current to resist flow forces, and some manufacturers do not permit PWM hold
> at all. Ask the valve supplier for the minimum hold current before you commit
> to 35 %.

---

## 4. Radio — and the single biggest cost decision

### Use a pre-certified module. This is not optional for a bootstrapped product.

FCC certification of an **intentional radiator** you designed yourself runs into
five figures and months of calendar time. A **pre-certified radio module carries
its own FCC ID**, and under modular approval rules you inherit it provided you
follow the module maker's antenna and layout conditions.

**That decision alone is the difference between a product you can afford to
launch and one you cannot.** Design the module in from day one — retrofitting a
certified module into a board laid out for a bare transceiver means a respin.

### Band and modulation

**915 MHz ISM (US), FSK.** Reasons, in order:

1. **Penetration and range** in a metal-rich environment beat 2.4 GHz
   comfortably. You are transmitting from a cab through glass and steel to a
   box bolted behind a grapple.
2. **Quiet band** compared to 2.4 GHz, which is saturated with WiFi and
   Bluetooth on every jobsite.
3. **Low latency.** Short FSK packets at 50 kbps arrive in a few milliseconds.

**Avoid LoRa** despite the temptation — its long range comes from spreading
factors that add tens of milliseconds of latency. Fine for telemetry, wrong for
a control the operator's thumb is driving. If you later add proportional
control, that latency becomes actively unpleasant.

**Avoid BLE** for the control path. Convenient for a phone-based config app,
but the wrong tool for a reliable low-latency link in this environment.

### Link parameters

| | |
|---|---|
| Heartbeat rate | 20 Hz (every 50 ms) |
| Watchdog timeout | 250 ms (five missed packets) |
| Packet | Pairing ID, sequence counter, button states, CRC |
| Pairing | Learned, stored in NVM, button-initiated |

### Connectionless, not connection-oriented — and this is the whole trick

The instinct is to think of this like a Bluetooth pairing: negotiate a
connection, maintain it, reconnect if it drops. **Do not build it that way.**

| | Bluetooth model | What this uses |
|---|---|---|
| Analogy | A phone call — dial, connect, redial if dropped | A radio station — broadcast on an ID, tune in |
| State | Connection maintained by both ends | **None** |
| Interference burst | *Disconnect*, then reconnect negotiation | Two packets lost out of five; nobody notices |
| Recovery time | Hundreds of ms to seconds | The next packet, 50 ms later |

The transmitter simply **broadcasts a packet every 50 ms whether or not anyone
is listening.** The receiver acts on any packet carrying the right pairing ID
and a good CRC. There is no session, no handshake, no connection state.

**Because there is no connection, there is nothing to lose.** A burst of
interference that would drop a Bluetooth link and strand the operator waiting
for reconnection costs this link two packets out of the five it takes to trip
the watchdog — the operator never knows it happened. And when the radio path
does break properly, recovery is not a negotiation, it is just the next good
packet arriving.

This is how RC models and industrial radio remotes work, and it is the correct
model for anything a human thumb is driving in real time.

The **pairing concept still applies** — you pair once and it remembers. But the
pairing is just a shared ID number stored in NVM, not a maintained session.

### What actually makes it reliable

1. **Statelessness** — nothing to re-establish
2. **Redundancy** — 20 Hz transmit, five consecutive misses before anything happens
3. **Frequency hopping** — spreads across the band so a narrowband interferer
   cannot camp on you. Worth specifying: in the US, frequency-hopping and
   digital modulation schemes in 902–928 MHz have more favourable power limits
   than narrowband operation. Confirm the specifics with the module vendor.
4. **Sequence numbers** — reject replays and out-of-order frames
5. **CRC** — reject corruption before it reaches the command path

### Where Bluetooth *does* belong

Not on the control path — but it is the right tool for a **configuration and
diagnostics app**: pairing setup, channel assignment, coil fault readout,
firmware update from a phone.

Two radios, two jobs. That is a Phase 3 nicety though; Phase 1 and 2 can
configure with a button and a status LED.

### Latency budget

Short FSK packets at 50 kbps arrive in single-digit milliseconds. With a 50 ms
transmit interval, worst-case command latency is about 50 ms — comfortably
inside what feels immediate for on/off control.

If proportional control is added later, raise the rate to 50 Hz. **This is
precisely why LoRa is the wrong choice** — its range comes from spreading
factors that add tens of milliseconds, which is invisible in telemetry and
unpleasant under a thumb.

---

## 5. Safety architecture — the part that must be right

This product commands hydraulic functions on someone else's machine. Four rules,
and none of them are preferences.

### Rule 1 — Loss of link de-energises everything

No valid packet for 250 ms → **all outputs off**, immediately. Flat pack,
dropped link, dead transmitter, interference: every one of them ends with the
attachment stopping.

### Rule 2 — Neutral-before-enable on power-up

On power-up the module refuses all commands until it has received a packet with
**every button released.** Otherwise a transmitter left in a toolbox with a
button pressed, or a stuck switch, actuates the attachment the instant the pack
goes in.

This is the same latch used on the machine's propel and PTO, for exactly the
same reason.

### Rule 3 — Pairing is unique and enforced

A packet whose pairing ID does not match is discarded silently. On a site with
three of your grapples, one transmitter must not drive another attachment.

### Rule 4 — The valve must be spring-centred

Rules 1–3 all assume that **removing current stops the function**. A detented or
hydraulically-latched valve breaks that assumption completely, and the product
is unsafe on one. State it in the manual, state it on the box, and refuse the
compatibility claim.

### Also fit

- A **physical power switch or E-stop** on the module — pulling the pack is the
  ultimate stop, but a switch is faster and does not get dropped in the mud
- A **status LED** legible in daylight: linked / no link / fault
- **Current sense per channel** for open-coil and short detection

---

## 6. Mechanical

### Attachment module

IP67 minimum, realistically IP69K given wash-down. Impact-resistant — this lives
on an attachment that gets dropped, dragged and loaded onto trailers.

**The battery bay is the hard part.** It must be sealed against water while
still accepting a standard M18 pack, and it must **lock** — a visible M18 pack
on an attachment left in a field will walk. A keyed or tool-release catch is not
optional for the rental market.

Insulate the bay. Lithium packs lose capacity badly below freezing, and this is
a cold-weather business. **Publish an honest cold-weather runtime figure**
rather than a room-temperature one; the first customer who finds out the hard
way will tell everyone.

### Joystick clip

One **common electronics pod**, a growing catalogue of **printed clamp shells**
for different grips.

This is the right structure for a low-volume startup: injection tooling for a
dozen grip shapes is impossible, printing a new shell is an afternoon. And
because the pod is common, adding support for a new machine is a design file,
not a production change.

**Publish the shell STLs.** Customers with unusual grips solve their own problem,
you get free coverage of machines you have never touched, and it is consistent
with publishing the attachment interface on the big machine. A competitor
tooling moulded plastic cannot follow you there.

---

## 6a. Grade control — what is real, and what is a different product

Worth taking seriously, because part of it is genuinely achievable and part of
it collides with the architecture that makes this product work.

### The structural problem

**Automatic grade control works by moving the blade or bucket** — sensing the
error and commanding lift or tilt to correct it. On a loader, lift and tilt are
*machine* functions, driven by the machine's own joystick and valve.

This product's entire value is that **it does not touch the machine.** So an
automatic system that has to command machine lift is, by definition, a different
product with a different installation and a different risk profile.

That is not a reason to abandon the idea. It is a reason to be precise about
which version you are building.

### Three tiers, honestly rated

| Tier | Needs | Touches the machine? | Verdict |
|---|---|---|---|
| **Cross-slope hold on an attachment with its own tilt** | IMU only | **No** | **Genuinely achievable. Build this.** |
| **Indicate-only** — show cut/fill, operator corrects | Elevation reference + display | No | Achievable, useful, cheap |
| **Full automatic 3D** | RTK GNSS + control of machine lift | **Yes** | Different product |

### Tier 1 is the real opportunity, and it needs no GPS at all

If the attachment has **its own tilt cylinder** — a grading bucket, a box blade
with hydraulic tilt, a land plane — then the module already controls that
function, and it can hold a cross-slope using nothing but a cheap IMU.

**No GPS. No base station. No subscription. No machine integration.** An
accelerometer and the tilt function you were already switching.

That is the same maths as `FB_BladeControl` in the loader project, running on a
much smaller processor. And for a small grading contractor it delivers most of
the practical benefit: a flat, consistent cross-slope without hunting the bubble.

### On GPS specifically

Standalone GNSS is ±1–3 **metres**. That is not grade control, it is navigation.
Useful grade needs **RTK**, which means either a base station on site or an NTRIP
correction subscription over cellular, plus RTK-capable receiver hardware. The
receiver alone is into the thousands, and the corrections are a recurring cost.

**For the small-site work this product serves, a rotating laser and receiver is
the better answer** — a few millimetres of accuracy, no subscription, no
cellular dependency, and it is what small grading contractors already own and
understand. If you add an elevation reference, add laser before GPS.

### The discipline point

**Do not put grade control in version 1.**

This is precisely the feature that turns a $5k product that ships into a $50k
product that does not. Functions 2, 3 and 4 are the thing people will buy today,
and shipping them earns the customers and revenue that make grade control
worth building.

Sequence it: **v1 functions. v2 cross-slope on tilt attachments. v3 elevation
reference, laser first.** Each tier is sellable on its own, and each one funds
the next — the same staged logic that made this product the right first step
over the machine.

---

## 7. Development phases

### Phase 1 — Proof it works (weeks, low hundreds of dollars)

Off-the-shelf everything. An M18 tool-side adapter plate, a dev-board MCU, a
relay or MOSFET board, a pair of pre-certified radio modules, a printed box.

**Goal: run a real attachment on a real machine.** Nothing else. Not pretty, not
sealed, not certified. This is where you find out what you did not know.

Do this alongside the competitor unit you bought, so you are comparing directly.

### Phase 2 — Real hardware (months)

Custom PCB with the certified radio module designed in. Proper enclosure and
battery bay. Peak-and-hold drivers with current sense. Firmware with the full
safety core. Printed clamp shells for the three or four most common grips.

Field-test on other people's machines. Their complaints are worth more than your
opinions.

### Phase 3 — Sellable (months)

FCC verification for the finished product (much cheaper with a certified
module). Enclosure sealing validation. Manual, installation guide, compatibility
list. Liability insurance and a conversation with an attorney about what you are
putting into the world. Packaging, pricing, first dealers.

---

## 8. Things that will bite you

| | |
|---|---|
| **Liability** | You are selling a control for hydraulics on machines you did not build. Get advice early, document the safety architecture, and keep the spring-centred-valve requirement absolutely explicit. |
| **Support burden** | A product business is warranty, returns and phone calls. Different work from building a machine, and it does not stop. |
| **Patents** | Check the competitors' portfolios before investing, particularly around the clip-on transmitter. An hour with an attorney now beats a letter later. |
| **Theft** | Locking battery bay. Rental fleets will ask about this first. |
| **Cold** | Test at temperature, and publish the honest number. |

---

## 9. Mounting: capturing grip geometry, and the "use the existing buttons" question

### Can we interface to the machine's existing grip buttons?

**On an OEM machine: no, and it would destroy the product.**

The buttons on a Bobcat or Deere grip are wired into that machine's harness and
read by that machine's controller. To use them you would have to tap into the
machine's wiring — which is *precisely* the brand-specific wiring-diagram
frustration this product exists to eliminate. You would need a different
adapter, a different pinout and a different install procedure per brand, and
you would be back to "only works on your machine."

**It fails the one-sentence test at the top of the README.** Reject it.

### The one legitimate middle path

Many skid steers carry a **7-pin or 14-pin attachment connector** at the front,
which already brings switched signals out to the attachment plate — no harness
work required. Where a machine has one, an **optional adapter cable** could feed
those existing signals into the module instead of the clip.

Treat that as an **accessory for the two or three most common pinouts**, never
the core product. The clip is what works everywhere; the adapter is a
convenience for machines that happen to be wired for it.

### Where Sure Grip / Bailey grips actually matter

Not here. Those are grips you **buy and install** — relevant to the track loader
project, where CAN grips with spare buttons feed our own controller as Tier 1
integration. That is already the plan in
`loader-control/docs/02-operator-interface.md`.

For this product, the customer already owns their grip and we are never
replacing it. Sure Grip publish technical guides and a CANopen EDS on their
[downloads page](https://suregripcontrols.com/downloads/); CAD would be a direct
request to them. Worth having for the loader — not needed for the clip.

### Do not model one grip

A shell modelled precisely to one handle fits exactly one handle. You do not
control which machines customers own, rubber boots vary by model year, and they
swell and wear.

**Use a compliant clamp with a parametric bore**, lined with elastomer, held by
a strap. One design covers a family of diameters; supporting a new machine means
changing a number, not commissioning CAD.

`mechanical/grip_clamp.scad` is that part — parametric on grip diameter, liner
thickness, button count and pitch. Measure, set one number, print, fit, adjust,
reprint. Twenty-minute loop.

> **Print it standing on end**, along the grip axis, so the C opening springs
> across layer lines rather than along them. Printed flat, it snaps at the
> opening on the first cold morning.

### Four cheap ways to capture a grip

| Method | Cost | Good for |
|---|---|---|
| **Masking tape wrap** | ~$0 | Wrap the grip, mark button positions during the Stage 0 shift, peel it off flat. You get a 2D development of the surface *and* the button locations, from the actual test. Do this one first. |
| **Contour gauge** | ~$10 | The comb-of-pins tool. Press on, trace the cross-section straight onto paper. Gives you the bore profile directly. |
| **Moldable thermoplastic** | ~$15 | InstaMorph / Polymorph. Press onto the grip for a physical negative you can measure or mould against. |
| **Phone photogrammetry or LiDAR** | ~$0 | Free apps produce a mesh easily good enough for a clamp shell. |

The tape wrap is the one to start with, because it comes out of the Stage 0 test
you are doing anyway — and it records where your thumb *actually* wanted the
buttons, not where you guessed they should go.
