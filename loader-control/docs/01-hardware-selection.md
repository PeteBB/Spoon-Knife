# Hardware Selection — Decisions and Rationale

Decisions made. Rationale given so you can overrule any of them with your eyes
open. Part numbers in these families get revised — confirm current orderable
numbers with the distributor before you cut a PO.

---

## The one decision that shapes everything else: go CAN-centric

The old way to build this machine is a star of analog wires: every joystick axis
is 3 wires, every button is a wire, every valve coil is 2 wires, all terminating
at the controller. A CTL built that way needs ~120 conductors through the boom
harness and the cab bulkhead, and every one of them is a warranty claim waiting
in a wet, vibrating, 40°C environment.

**Build it on CAN instead.** Joysticks, valve sections, display and engine all
talk over two twisted pairs. The controller keeps analog inputs only for the
sensors that genuinely are analog (pressures, temps, angles).

What this buys you, in order of how much it matters:

1. **Harness reliability.** The single biggest source of field failures on this
   class of machine is connections, not components. Removing 80% of the
   conductors removes 80% of the problem.
2. **Buttons become free.** You asked for toggle and trigger buttons on the
   grips driving functions and aux. On a CAN grip, adding a button costs
   nothing in the harness — it is a bit in a message that is already being
   transmitted. This is what lets the configurable button mapping in
   `docs/02-operator-interface.md` exist at all.
3. **Diagnostics you cannot get any other way.** A CAN valve reports its own
   spool position, coil health and supply voltage. When a section misbehaves,
   the display tells the dealer which section and why, instead of a tech
   putting a meter on coils for two hours.
4. **Redundancy handled at the source.** A CAN joystick does its own
   dual-element cross-check internally and reports a fault flag. You still
   check it (see `FB_AxisConditioning`), but you are checking a device that is
   already checking itself.
5. **Assembly and service.** Two connectors on a valve bank instead of sixteen.

Cost: CAN valve actuation and CAN grips carry a real price premium per unit,
and you take on a CAN bus-loading and network-management problem you would not
otherwise have. For a machine positioned to beat the incumbents on controls,
this is the right side of that trade.

---

## Machine controller — **IFM ecomatController, CR711S**

The safety-capable variant of IFM's CODESYS controller family. One controller,
running both the standard application and the safety-rated interlock logic in
its certified partition.

**Why IFM over the alternatives:**

| | IFM CR711S | Danfoss PLUS+1 MC050 | Parker IQAN MC43 | TTControl HY-TTC 580 |
|---|---|---|---|---|
| Language | CODESYS 3.5 (IEC 61131-3) | PLUS+1 GUIDE (graphical) | IQANdesign | CODESYS / C |
| Code portability | **High** — standard ST | None — proprietary | None — proprietary | High |
| Safety rating | SIL2 / PL d | Available on some models | Available | **Best in class** |
| Toolchain cost | Low | Low | License per seat | High |
| Unit cost | **Low–mid** | Mid | Mid–high | **High** |
| Display in same project | **Yes** | Yes | Yes | Separate |

The deciding factor is **portability plus safety in one toolchain**. Everything
in `src/st/` is standard IEC 61131-3. If IFM disappoints you in three years, you
port the HAL and keep the control logic — the part that took the tuning effort.
Choose PLUS+1 or IQAN and the logic is trapped in the vendor's editor forever.

TTControl is the better controller in absolute terms and is what a Tier 1 OEM
would use. It is roughly 3× the price and the toolchain expects a full-time
functional-safety engineer. Revisit it if you get to volume.

**Second controller:** add a small IFM CR-series I/O expander at the rear of the
machine for engine-bay and boom sensors, so those signals join the bus locally
instead of running forward. One more node, forty fewer conductors.

---

## Display — **IFM ecomatDisplay, 7" CR12xx**

Same CODESYS project as the controller. This is a bigger deal than it sounds:
one project, one download, shared variable definitions, no protocol to invent
between controller and screen, no second toolchain to learn.

7" is the right size — big enough for a live-I/O service screen and an
attachment-profile editor, small enough not to eat the cab. Specify the
sunlight-readable variant; a CTL cab is glass on three sides.

---

## Joysticks — CANopen grips, **Sure Grip Controls** or **Curtiss-Wright / Penny+Giles JC6000**

Both build for exactly this application. Specify:

- **Dual-axis Hall, dual redundant elements per axis**, CANopen or J1939 output
- **Proportional thumb rocker or slider** on the right grip for aux flow —
  proportional, not on/off. On/off aux is the single most-complained-about
  control on cheap machines.
- **Index trigger** on the right grip
- **8–10 momentary buttons minimum** across the two grips, plus a two-position
  toggle each — you will use fewer at launch and be grateful for the spares in
  two years
- **Friction detent or spring-return**, spring-return for both
- IP67 boot, cold-rated grease

Do not buy analog grips to save money. The harness saving alone closes the gap,
and the button count you asked for is not practical on analog.

---

## Hydraulics

| Function | Selection | Note |
|---|---|---|
| Propel pumps | **Danfoss H1 tandem, 45–53 cc**, electric displacement control | Current-gen closed-circuit hydrostat. EDC coils driven from CR711S current outputs. |
| Track motors | **Danfoss H1B bent-axis, two-position** | Gives real two-speed without a gearbox. |
| Work pump | Load-sensing axial piston | Sized for high-flow aux from day one — see below. |
| Loader + aux valve | **Danfoss PVG 32 with PVED-CC actuation** | CAN-commanded sections. This is the piece that makes the whole CAN-centric architecture work. |
| Aux couplers | Flat-face, high-flow rated | Plus the electrical/CAN attachment connector. |

**Size the work pump for high flow at launch, even if you sell standard flow.**
High-flow capability is what puts mulchers, cold planers and stump grinders on
your machine, and those attachments are where the margin and the customer
lock-in are. Retrofitting flow capacity later means a new pump, new valve and
new plumbing; specifying it now costs a pump upgrade.

---

## Engine

**Kubota V3307-CR-T** (~74 hp, Tier 4 Final / Stage V) or **Yanmar 4TNV98C**.

Both are proven in this class, both have mature J1939 interfaces, both have
dealer networks that will still exist in ten years. Kubota edges it on parts
availability in North America; Yanmar on the quality of its application
documentation, which matters to you specifically because you are writing the
TSC1 throttle and anti-stall integration.

Get the **engine application manual and the J1939 interface spec** in writing
before you commit. Every manufacturer deviates from generic J1939 somewhere,
and finding out which PGN they moved after the harness is built is a bad week.

---

## Sensors

| Signal | Type |
|---|---|
| Lift arm angle, tilt angle | Rotary Hall, non-contact, IP69K |
| Charge / loader / aux pressure | 0.5–4.5 V ratiometric, or CAN |
| Hydraulic oil temp | PT1000 or thermistor |
| Track speed L/R | Hall pickup on motor shaft |
| Fuel level | Resistive sender |

Non-contact rotary sensors for the arm and bucket angle. String pots are cheaper
and will not survive a CTL's life. The self-level and return-to-dig features
depend entirely on these two sensors staying honest, and they are the features
customers will notice on the demo ride.

---

## Attachment identification

Put a **CAN connector on the attachment plate** carrying power, ground and CAN.
Dumb attachments ignore it. Your attachments carry a cheap CAN node that reports
an ID, and the controller loads flow limits, pressure limits, ramp rates, the
right button mapping and the right display screen automatically.

This is the highest-leverage thing on the whole hardware list. It is a few
dollars of connector and a $15 node per attachment, and it is the difference
between selling a loader and selling a system.

---

## Bus layout

| Bus | Speed | Nodes |
|---|---|---|
| **CAN1 — Machine** | 250 kbit/s | Joysticks, display, PVED-CC valve sections, rear I/O expander |
| **CAN2 — Powertrain** | 250 kbit/s | Engine ECU (J1939), aftertreatment |
| **CAN3 — Attachment** | 250 kbit/s | Attachment ID node, smart attachments |
| **CAN4 — Service / telematics** | 500 kbit/s | Diagnostic port, telematics modem, grade control |

Keep the engine on its own bus. Engine ECUs are chatty and you do not want
aftertreatment traffic competing with joystick messages for bus time. Keep the
attachment bus separate too — a customer-fabricated attachment with a badly
behaved node must not be able to take down the machine's controls.

Terminate properly at both physical ends of each bus, 120 Ω, and put the
diagnostic connector where a tech can reach it without removing a panel.
