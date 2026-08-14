# Acquisition Plan — What to Buy, In What Order

> Prices are rough ranges to budget against, not quotes. Everything here is a
> category plus what it must do — confirm current availability and part numbers
> before ordering.

The ordering matters more than the list. **Each stage answers a question, and
you should not buy the next stage until the previous one has answered it.**

---

## Stage 0 — The $50 question, before you buy anything else

**Question: does a joystick-mounted control actually feel right for a full
shift?**

This is your headline differentiator and the one thing that cannot be
desk-checked. If it turns out to be awkward with a glove on, in the cold, while
your thumb is also working the aux rocker — the product changes shape, and you
want to know that *now*, not after the electronics exist.

| Item | Notes | Rough cost |
|---|---|---|
| Momentary pushbuttons ×6 | Panel-mount, the kind you can actually feel with a glove | $10 |
| Scrap of plastic, hose clamp, tape, zip ties | The uglier the better | $10 |
| Bell wire or old cable | Run it to a bench, or to nothing at all | $10 |
| A pen and a notebook | Genuinely the important part | — |

**It does not need to control anything.** Tape it to your grip, run a normal
shift, and pay attention to: can you find the buttons without looking, does your
hand cramp, does it get in the way of how you already hold the stick, does it
survive getting in and out of the cab, and where do you *wish* the buttons were.

Iterate the shape three or four times before anything electrical exists.

---

## Stage 1 — Bench proof

**Question: does the radio hold, and does peak-and-hold actually hold a real
coil?**

Prove this on a bench. **Do not plumb hydraulics yet** — a single solenoid coil
on a bench answers the electrical question completely, and it costs a fraction
of a valve.

### Electronics

| Item | What it must do | Rough cost |
|---|---|---|
| MCU dev boards ×2 | One transmitter, one receiver. Anything you already know. | $20–40 |
| Sub-GHz FSK radio modules ×2 | 915 MHz, FSK, easy library support. RFM69-class is the usual prototyping choice. | $20–40 |
| **M18 battery adapter / dock** | Tool-side contact block. Sold cheaply for DIY projects — this is what makes it an M18 product. | $10–25 |
| Buck converter, 18 V → 12 V, ≥5 A | Must survive a 20 V fresh pack and hold 12 V under a coil pull-in surge | $15–30 |
| N-channel MOSFET modules or a driver board | Low-side switching, PWM-capable, adequately heatsinked | $15–30 |
| **Flyback diodes** | **Non-optional** — see the warning below | $5 |
| Current sense breakout (INA226-class) | Proves the open-coil / short detection in `safety_core.c` | $10–20 |
| **One 12 V hydraulic solenoid coil** | The actual load you are designing for. Buy the coil alone, not the valve. | $25–60 |
| Breadboard, jumpers, terminal blocks, fuses | | $30 |

> **Flyback diodes across every solenoid, from the very first bench test.**
> A solenoid is an inductor. Switching it off dumps a large reverse voltage
> spike straight into your MOSFET, and it will destroy it — usually on the
> bench, occasionally weeks later in the field, which is worse. This is the most
> common way people kill a first prototype.

### Test gear

| Item | Why | Rough cost |
|---|---|---|
| Multimeter | If you don't already have a decent one | $30–80 |
| **USB oscilloscope or logic analyser** | **Buy this.** You cannot tune peak-and-hold or debug radio timing blind, and cheap ones are genuinely good enough. | $50–120 |
| Soldering iron, solder, heatshrink | If not already on hand | $40–100 |
| Bench power supply, adjustable | Optional but makes coil testing much easier | $50–90 |

**Stage 1 total: roughly $300–600**, less whatever you already own.

### What Stage 1 proves

1. Peak-and-hold: measure the actual hold current your coil needs. **The 35%
   figure in the design doc is an assumption and this is where it gets
   replaced with a number.**
2. Radio range and reliability, cab to attachment position, through steel.
3. The safety core running for real — watchdog timeout, neutral-before-enable,
   pairing rejection.
4. Real power draw, so the runtime figures stop being arithmetic.

---

## Stage 2 — On a real attachment

**Question: does it work in the dirt?**

| Item | Notes | Rough cost |
|---|---|---|
| DC stack valve or diverter, 12 V, **spring-centred** | The hard requirement. Do not test on a detented valve — you will build the wrong reflexes. | $150–400 |
| Deutsch DT connector kit | Pins, sockets, housings, seals | $30–60 |
| **Deutsch crimp tool** | Buy the real one. Pliers-crimped pins fail in the field and you will chase the fault for a week. | $50–150 |
| Weatherproof enclosure, IP67 | Off-the-shelf ABS box plus cable glands for now | $20–50 |
| Hose, fittings, quick couplers | Only if plumbing a test rig rather than borrowing an attachment | $100–300 |

**A borrowed or existing multifunction attachment is worth more than anything
you can buy here.** A grapple with rotate, or anything with a second function,
gets you to a real test far faster than building a rig.

**Stage 2 total: roughly $250–900** depending on how much plumbing you need.

---

## Stage 3 — Competitor teardown

| Item | Why | Rough cost |
|---|---|---|
| Skid Sync U400 or Skid Steer Genius WACT | Use it on a real job. Every annoyance is a line in your spec. | $500–1,500 |

Buy this **early**, in parallel with Stage 1 — the information is worth more the
sooner you have it, and it also tells you what the market currently pays.

---

## Tools worth owning, not renting

| | Why |
|---|---|
| **3D printer** | You will iterate clamp shells twenty times. A print service makes that a two-week loop instead of an overnight one. Decent modern machines are $200–400 and it pays for itself in iterations alone. |
| Deutsch crimper | See above. Non-negotiable for anything that goes on a machine. |
| Scope / logic analyser | You cannot tune what you cannot see. |

---

## What NOT to buy yet

Discipline matters more here than the list above. **None of these belong in the
first few hundred dollars:**

| Not yet | Why |
|---|---|
| **The pre-certified radio module** | Prototype radio and production radio are different decisions. Get the concept working first, then choose the module you will certify with. Do not over-invest in a Phase 1 radio. |
| **Custom PCB fabrication** | Breadboard until the design stops changing. It will change a lot. |
| **Enclosure tooling** | Off-the-shelf boxes until the internals are settled. |
| **Anything laser** | That is v2. Ship functions 2/3/4 first. |
| Bulk anything | You do not know the final BOM yet. |
| FCC testing | Nothing to test until Phase 2 hardware exists. |

---

## Realistic totals

| Stage | Range |
|---|---|
| 0 — clip ergonomics | ~$50 |
| 1 — bench proof | $300–600 |
| 2 — real attachment | $250–900 |
| 3 — competitor unit | $500–1,500 |
| Tools (printer, crimper, scope) | $300–700 |
| **All in** | **roughly $1,400–3,750** |

That lands comfortably inside the $5k you named for a working, proven
prototype — with the competitor research and the tooling included, and with room
left over for the parts you break.

---

## The real gate is not money

Before ordering anything, confirm you have:

1. **Access to a machine with auxiliary hydraulics**, for enough time to test
   properly — not a favour you can call in once
2. **A multifunction attachment** to test on, borrowed or owned
3. **Somewhere to work** on it, in weather, repeatedly

If any of those three is missing, solve it before spending. **The parts are the
cheap part.** A prototype you cannot test is worse than no prototype, because it
feels like progress.

---

## Suggested sequence

1. **Stage 0 today.** Buttons and tape. Run a shift.
2. **Order the competitor unit now** — it ships while you do Stage 0.
3. **Stage 1 bench kit** once the clip shape feels right.
4. Get `safety_core.c` running on the bench, with real coil measurements
   replacing the assumed constants.
5. **Stage 2** onto a real attachment.
6. Only then start thinking about Phase 2 hardware and certification.
