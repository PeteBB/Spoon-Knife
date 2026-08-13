# Sourcing, Purchase Points and Supply Strategy

**Scope note:** this lists channels, portals and the questions to ask. It does
not quote prices, lead times or contact names. Those change month to month and
come out of an RFQ — anything I stated here would be stale or invented. Verify
every part number against the supplier's current catalogue before you commit.

---

## 1. The thing that will actually bite you is not the PLC

Rank your supply risk honestly, because the intuitive answer is wrong:

| Component | Supply risk | Why |
|---|---|---|
| **Engine** | **Severe** | Allocation-based. Requires an OEM agreement and a rolling forecast. Longest lead time on the machine. Cannot be substituted without redesigning mounts, cooling, plumbing and re-doing emissions paperwork. |
| **Valve bank w/ electronic actuation** | **High** | Semiconductor content in the PVED modules. Historically the constrained item in this stack, ahead of the controller. |
| **Hydrostat pumps/motors** | **Moderate–high** | Long lead, and switching families is a re-plumb plus a full recalibration. |
| Controller | **Low–moderate** | Genuine second sources exist — see §4. |
| Joysticks | **Low** | Three credible interchangeable suppliers. |
| Display | **Low** | Interchangeable within CODESYS. |
| Sensors, connectors, harness | **Low** | Commodity, multi-sourced. |

Plan your buffer stock and your supply agreements against that ranking, not
against unit cost. The cheap part with one source stops the line just as hard
as the expensive one.

---

## 2. The channel trap — read this before you buy anything

Search for `CR711S` and you will find it on eBay, Radwell, Kempston, and a
dozen broker sites, in stock, ready to ship. **That channel is correct for
prototypes and disastrous for production.**

Brokers and grey-market resellers give you:
- no allocation priority when the market tightens — you are last in line
- no product change notification (PCN) or end-of-life notification (PDN)
- no warranty path you can pass through to your customer
- no traceability, which matters the day you need to know which machines got
  which firmware revision
- no application engineering support

For a machine you are selling with your name and your warranty on it, you need
a **direct OEM account with the manufacturer**, or an account with their
franchised distributor. Buy prototypes off the shelf; do not build a business
on it.

---

## 3. Who to contact, and what to ask for

**Ask for a Field Application Engineer, not a salesperson.** This is the single
most useful thing in this document. Every supplier below fields FAEs who will
do integration support, sizing, and often free on-site commissioning help,
because they want the design win. A salesperson sends you a price list; an FAE
sends you a working configuration. Say the words "we are designing a new
compact track loader and evaluating suppliers" and you will get one.

### Controller and display — ifm

- **Portal:** [ifm.com/us](https://www.ifm.com/us/en/product/CR711S)
- **Route:** ifm sells direct in North America with a regional field sales
  force. Contact through the site and **specifically request the mobile /
  off-highway controls group.** ifm's volume business is industrial sensors;
  if you land with a factory-automation rep you will get a polite dead end.
- **Ask for:** OEM pricing at your projected volume, the CODESYS licensing
  terms, the safety manual and certificate for the CR711S safety partition,
  lifecycle status and PCN/PDN commitment, and an FAE for the first bring-up.

### Hydraulics — Danfoss Power Solutions

- **Distributor finder:** [powersource.danfoss.com/where-to-buy](https://powersource.danfoss.com/where-to-buy)
- **General contact:** [danfoss.com/en-us/contact-us](https://www.danfoss.com/en-us/contact-us/)
- **Route:** Danfoss runs a franchised distributor network plus direct OEM
  accounts. For an H1 hydrostat you want the **direct OEM route with their
  application engineering group** — hydrostat sizing for a CTL is genuinely
  their expertise and they will do the calculations for you.
- **Ask for:** H1 pump/motor sizing for your machine weight, track geometry and
  target ground speeds; PVG 32 stack configuration; PVED-CC ordering codes; and
  a supply agreement rather than spot POs.

> **Integration detail worth knowing now:** PVED-CC actuators are PLUS+1
> compliant and are parameterised with the **PLUS+1 GUIDE service tool**, even
> though we chose CODESYS for the machine controller. You will need a GUIDE
> licence and dongle as a *service tool* — for setting section flow scaling,
> ramps and CAN node IDs — not as your development environment. Budget for it
> and factor it into your production line and dealer service kit.

### Joysticks

Two credible suppliers, both proven in this exact application:

- **Sure Grip Controls** — a company of **Bailey Hydraulics**, which is also
  your purchase point. JSC CAN series available in CANopen and analog.
  [Product overview](https://www.oemoffhighway.com/operator-cab/operator-interface/joysticks/product/22880531/sure-grip-controls-inc-sure-grip-controls-releases-new-canopen-analog-versions-of-its-jsc-joystick-base)
- **Penny + Giles (Curtiss-Wright)** — the **JC8000** is the strong candidate:
  dual-redundant 12-bit Hall, J1939 CAN, and it is *explicitly engineered for
  skid steer loader controls* and for operators used to hydraulic joysticks.
  That is our application described back to us.
  [JC8000](https://www.oemoffhighway.com/operator-cab/operator-interface/joysticks/operator-interface/joysticks/product/10738553/penny-giles-controls-ltd-jc8000-high-strength-electronic-joystick-controller)

Get evaluation samples of both and put them in front of operators before you
choose. Grip ergonomics is the one thing on this machine you cannot fix in
software, and it is decided in about ninety seconds of someone holding it.

**Ask for:** button/switch population options, the CANopen or J1939 object
dictionary / message specification, boot sequence and node-ID assignment, IP
rating and cold-temperature spec, and the redundancy fault-reporting behaviour
so `FB_AxisConditioning` can consume it properly.

### Engine — start here first, it has the longest fuse

- **Kubota Engine America:** [kubotaengine.com](https://www.kubotaengine.com/engines/industrial-engines/) —
  V3307-CR-T-E5, 55.4 kW / 74.3 hp, EPA/CARB Tier 4 Final + EU Stage V.
- **Yanmar America** — industrial engines division, for the 4TNV98C.

Both sell OEM engines through a distributor and dealer network distinct from
their equipment business. **Open this conversation before any other**, because
engine allocation is the constraint that will cap your production ramp, and
because the J1939 interface spec you need for the anti-stall and throttle code
comes out of this relationship.

**Ask for:** the OEM application manual, the **J1939 interface specification in
writing**, installation requirements for emissions compliance, cooling package
guidance, allocation terms against a forecast, and what forecast accuracy they
expect from you.

---

## 4. Design for second source now, not during the shortage

**The CODESYS decision in `01-hardware-selection.md` is your supply-chain
insurance, and it only pays out if you use it.**

ifm CR711S, TTControl HY-TTC and Epec all run CODESYS / IEC 61131-3. Because
all machine logic lives in `src/st/` and all platform binding lives in
`src/hal/`, a controller swap is a HAL rewrite and a recompile — days, not a
redesign. But that is only true if you **prove it once during development**.
Port the HAL to a second controller, run it on the bench rig, and shelve it.
That week of work is the cheapest insurance on the whole program.

| Item | Primary | Qualified alternate | Swap cost |
|---|---|---|---|
| Controller | ifm CR711S | TTControl HY-TTC / Epec 5050 | Low — HAL only |
| Display | ifm ecomatDisplay | any CODESYS-capable display | Low |
| Joysticks | Penny+Giles JC8000 | Sure Grip JSC CAN | Low — abstract the CAN parsing behind one FB |
| Sensors | — | multi-source from day one | Low |
| **Valve bank** | Danfoss PVG 32 | *(hard)* | **High — re-plumb + recalibrate** |
| **Hydrostat** | Danfoss H1 | *(hard)* | **High** |
| **Engine** | Kubota V3307 | Yanmar 4TNV98C | **High — dual mechanical design** |

The bottom three are where you sign supply agreements, because you cannot
engineer your way out of them quickly. The top four are where you stay flexible
and refuse to be locked in.

Abstract the joystick CAN parsing behind a single function block from the
start. It costs nothing today and it is what makes the grip supplier a
negotiable commodity instead of a dependency.

---

## 5. Volume tiers — what changes as you ramp

| Stage | Units | Channel | What to have in place |
|---|---|---|---|
| **Prototype** | 1–5 | Distributor / off-the-shelf. Broker is acceptable here. | Nothing. Buy fast, iterate. |
| **Pilot** | 10–50 | Direct OEM accounts opened, first forecast submitted | Engine allocation agreement. FAE relationships. Second controller qualified on the bench. |
| **Production** | 100+ | Supply agreements, scheduled orders, possible VMI/consignment | PCN/PDN notification agreements. Buffer stock on the long-lead three. Approved-vendor list with alternates already qualified. |

The mistake that kills small OEMs: staying on distributor spot-buys because it
works fine at ten units, then discovering at eighty units that you have no
allocation priority and a 40-week engine lead time. **Open the direct accounts
one tier before you need them.** Suppliers are far more receptive to a startup
with a credible forecast than to one placing a panic order.

---

## 6. Two obligations that are yours, not your suppliers'

1. **Emissions compliance is the machine OEM's obligation.** Your engine
   supplier sells you a certified engine and an installation specification.
   Meeting that specification — cooling, intake restriction, exhaust
   backpressure, aftertreatment packaging — and the resulting machine-level
   compliance is on you. Get the installation requirements early; they
   constrain your engine bay layout, and discovering that after the frame is
   welded is expensive.
2. **Lifecycle notification.** Negotiate PCN/PDN terms into your supply
   agreements. A controller revision that changes CAN timing behaviour, pushed
   without notice, will find you through warranty claims rather than through
   your inbox.

---

## 7. Where to meet all of them in two days

Trade shows are the highest-bandwidth way to open every one of these
relationships at once — the FAEs are all on the floor and they are there
specifically to find design wins.

- **CONEXPO-CON/AGG** — Las Vegas, triennial
- **bauma** — Munich, triennial
- **The Utility Expo** — Louisville, biennial

Check current dates; the cycles shift. Walk in with your machine concept, a
one-page spec, and a projected volume, and ask each booth for their off-highway
FAE.

---

## Sources

- [ifm CR711S product page](https://www.ifm.com/us/en/product/CR711S)
- [Danfoss PowerSource — find a distributor](https://powersource.danfoss.com/where-to-buy)
- [Danfoss contact centre](https://www.danfoss.com/en-us/contact-us/)
- [Danfoss PVG 32 proportional valves](https://www.danfoss.com/en/products/dps/hydraulic-valves/directional-control-valves/compensated-proportional-valves/pvg-32-proportional-valves/)
- [Danfoss PVE electrohydraulic actuators](https://www.danfoss.com/en/products/dps/hydraulic-valves/directional-control-valves/compensated-proportional-valves/pve-electrohydraulic-actuators/)
- [Danfoss PVG 32 technical information (PDF)](https://assets.danfoss.com/documents/latest/406946/BC152886483664en-001602.pdf)
- [Penny + Giles JC8000 joystick controller](https://www.oemoffhighway.com/operator-cab/operator-interface/joysticks/operator-interface/joysticks/product/10738553/penny-giles-controls-ltd-jc8000-high-strength-electronic-joystick-controller)
- [Sure Grip Controls JSC CAN series](https://www.oemoffhighway.com/operator-cab/operator-interface/joysticks/product/22880531/sure-grip-controls-inc-sure-grip-controls-releases-new-canopen-analog-versions-of-its-jsc-joystick-base)
- [Kubota Engine America — industrial engines](https://www.kubotaengine.com/engines/industrial-engines/)
- [Kubota V3307-CR-T-E5 specification](https://engine.kubota.com/products/detail?ln=en&id=211)
