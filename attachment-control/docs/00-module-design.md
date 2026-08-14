# Module Design — System Map

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
