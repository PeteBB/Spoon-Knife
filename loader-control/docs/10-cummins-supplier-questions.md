# Cummins — Supplier Call Preparation

Working checklist for the engine supplier conversation. Priority markers:

- 🔴 **Blocking** — work stops or gets rebuilt without this
- 🟡 **Important** — shapes the design, but can follow
- ⚪ **Housekeeping** — needed eventually

---

## 0. Before you dial

### Get routed to the right person

Ask for **off-highway / industrial OEM application engineering**, not general
sales. Cummins' volume business is on-highway; landing with the wrong group
wastes the call. Also establish early: **are we served direct, or through a
distributor at our volume?** Distributors are the channel for smaller OEMs, and
if that is the answer you want the distributor's application engineer on the
next call.

### Have this ready — it changes how you get treated

Suppliers triage by how real you look. A one-page machine spec makes you a
prospect instead of a tyre-kicker:

| | |
|---|---|
| Machine type | Rubber-tracked utility loader / tractor |
| Operating weight | 11,000–13,000 lb |
| Power required | 100–110 hp continuous at the flywheel |
| Loads | Hydrostatic propel + load-sensing work hydraulics + 540 rear PTO (40–50 hp at the shaft) |
| Engine orientation | Longitudinal — pump drive off the front, PTO off the rear |
| Duty cycle | Heavy intermittent: loading, drawbar tillage, dozing |
| Markets | North America (Tier 4 Final); EU (Stage V) if applicable |
| Volume | Year 1: __ / Year 2: __ / Year 3: __ |
| Timeline | Prototype: __ / Production: __ |

**Be straightforward about being a startup.** They will work it out, and
credibility is worth more than looking bigger than you are. A small builder with
a clear spec and honest numbers gets better engineering support than one
inflating a forecast.

---

## 1. Engine selection and rating

- 🔴 Confirm **B4.5** is the right engine for 100–110 hp continuous with the PTO
  duty described. If not, what is?
- 🔴 **Which rating curve?** Cummins publishes several per engine. Which is
  appropriate for this duty cycle, and what is the continuous vs intermittent
  distinction at our power?
- 🔴 Torque curve — peak torque, and at what speed? *(This drives the PTO
  gearbox ratio and the anti-stall tuning.)*
- 🟡 Is there a specific off-highway variant / control module we should spec?
- 🟡 Can **one engine configuration cover both Tier 4 Final and Stage V**, or do
  we need separate builds per market?
- 🟡 Fuel consumption map at our expected operating points
- ⚪ Dry weight and CG location *(feeds the balance study)*

---

## 2. Power take-off provisions — the machine-specific one

**This is the question most likely to change the machine layout, and the one a
generic sales conversation will not cover.** We are taking power off *both ends*
of the crankshaft.

- 🔴 What can we drive **off the front of the crank** (hydrostatic + work pumps)?
  Available drive provisions, and the **power and torque limit** at that end?
- 🔴 **Allowable side load and overhung moment on the crankshaft** — a belt or
  gear pump drive imposes both, and exceeding it kills the front main bearing.
- 🔴 Rear **flywheel housing and flywheel SAE sizes** available, and what we can
  take through them for the PTO clutch.
- 🔴 Can we take full-rated PTO power off the rear **while** driving pumps off
  the front? Is there a combined limit?
- 🟡 Is there a factory front accessory drive option, or do we design our own?
- 🟡 Torsional vibration analysis — **do they provide it, require it, or expect
  us to commission it?** *(A PTO driveline with a clutch and a hydrostatic pump
  drive on the same crank is exactly the case where torsional resonance bites.
  Do not skip this.)*

---

## 3. J1939 interface — blocks the control software

Every one of these is 🔴. The anti-stall, throttle and PTO code cannot leave
placeholder state without them.

- **The complete J1939 interface specification document, in writing.**
- Which **PGNs and SPNs** are supported, and **where does the implementation
  deviate from generic J1939?** *(Everyone deviates somewhere.)*
- **TSC1** — is engine speed request supported? Torque limit request? What
  source address and priority should our controller use?
- Is there an **enable, validation or handshake** the ECM requires before it
  will accept TSC1? Any timeout behaviour if our messages stop?
- **Broadcast rates** for EEC1, EEC2, ET1 and the rest.
- **Multi-source arbitration** — what happens if our controller and another node
  both send TSC1?
- Required **CAN baud rate and termination** at the ECM.
- **DM1 / DM2** fault code handling — and do we get the fault code list with
  plain-language text we can put on our display?
- Is the engine started/stopped by a **hardwired keyswitch, or over CAN?** What
  does the ECM need on power-up?
- 🟡 **Is there an OEM parameter or calibration tool** (INSITE or similar), does
  it need a licence, and is it restricted to Cummins dealers? *(Same trap as the
  PLUS+1 GUIDE service tool — budget for it in the production line and every
  dealer service kit.)*

---

## 4. Installation requirements

- 🔴 The **engine installation / application manual.**
- 🔴 **Maximum continuous and intermittent operating angles** — pitch and roll.
  *(A tracked machine works slopes. Oil pickup and drainback set hard limits and
  they will constrain what we can claim.)*
- 🔴 **Heat rejection** to coolant and to charge air, at our rating.
- 🔴 **Minimum cooling airflow, maximum allowable core restriction, and maximum
  top-tank temperature.** *(Feeds the cooling package layout, which needs doing
  before the frame.)*
- 🔴 **Maximum intake restriction** and **maximum exhaust backpressure.**
- 🟡 Is the **reversing cooling fan** arrangement acceptable to them, and does it
  affect the cooling validation? *(Ours is hydraulically driven and periodically
  reverses — worth surfacing rather than discovering in a warranty dispute.)*
- 🟡 Fuel system: supply and return requirements, **fuel cooling** needs, lift
  pump, water separator.
- 🟡 Electrical: alternator options and rating, starter, system voltage, ECM
  power and grounding requirements.
- ⚪ Air cleaner sizing and service indicator provisions.

---

## 5. Aftertreatment and regeneration

- 🔴 What is the **aftertreatment configuration** at our rating — DPF only, or
  DPF plus SCR? **Is DEF required?**
- 🔴 **What does regeneration require from our controller?** Inhibit inputs,
  operator notification, permissions, lamps?
- 🔴 **Can regeneration be inhibited by the operator, and for how long?**

> **Push hard on the inhibit question.** A high-temperature regeneration in a
> barn, in dry crop residue, or in standing hay is a fire risk, and our buyers
> work in all three. We need a defensible inhibit strategy and a clear
> understanding of what happens when the inhibit runs out. Get this answer in
> writing.

- 🟡 Regeneration strategy — passive, active, parked? How often at our duty
  cycle? Does a low-load ag duty cycle cause soot loading problems?
- 🟡 **DEF tank sizing** for our duty cycle, and freeze protection requirements.
- 🟡 Exhaust outlet position options, **thermal shielding requirements**, and
  minimum clearances to combustible material.
- ⚪ Aftertreatment service intervals and ash cleaning.

---

## 6. Emissions compliance — whose obligation is what

- 🔴 **What is our obligation as the machine OEM, and what do we inherit from
  the certified engine?**
- 🔴 Do we need our own EPA / CARB registration, or do we operate under their
  certificate?
- 🟡 **Labelling requirements** on the machine.
- 🟡 What documentation must we retain, and for how long?
- 🟡 Same questions for **EU Stage V**, if that market is in scope.
- 🟡 What installation deviations would **void the emissions certification?**
  *(This is the one that quietly bites — an intake or exhaust change made for
  packaging reasons can invalidate the cert.)*

---

## 7. Commercial and account

- 🔴 **Direct or distributor** at our volume?
- 🔴 **Minimum annual volume** for an OEM account.
- 🔴 **How do we buy one or two engines for the prototype, before a production
  account exists?** *(Ask explicitly. It is the immediate blocker, and there is
  usually a path.)*
- 🟡 Pricing structure and volume breaks.
- 🟡 **Lead time and allocation policy** at our volume — and what forecast
  accuracy do they expect from us?
- 🟡 What happens if we miss forecast, in either direction?
- ⚪ Payment terms.

---

## 8. Support, warranty and lifecycle

- 🔴 **Who is our application engineer, and do they work for Cummins or the
  distributor?** Get a name.
- 🟡 Is there an **installation review or approval step** before production, and
  is it required for warranty?
- 🟡 **Warranty** — terms, who administers claims, and what is our obligation as
  the machine OEM?
- 🟡 **Service training** availability for our dealers.
- 🟡 **Product change notification (PCN) and end-of-life (PDN)** terms — we need
  notice of anything that changes CAN behaviour or installation envelope.
- 🟡 **How long will the B4.5 remain in production at this emission level?**
- 🟡 What is the **next emissions step**, when, and what is the migration path?

---

## What a good call looks like

Leave with:

1. A **named application engineer** and their direct contact
2. The **installation / application manual**
3. The **J1939 interface specification**, or a definite path to it
4. A **budgetary quote** at your stated volume
5. A **route to prototype engines** that does not require a production account
6. Clear answers on **crankshaft power take-off limits at both ends**
7. A straight answer on **regeneration inhibit**

## Answers that should worry you

- Reluctance to release the **J1939 spec** without a signed agreement — you
  cannot design the control system blind, and it is not proprietary magic
- "We'll get back to you" on **who your application engineer is** — that usually
  means there isn't one at your volume
- **Minimum volumes far above your plan**, with no distributor path offered
- Vagueness on **regeneration inhibit** — this one is a safety and liability
  issue, not a preference
- No answer on **crankshaft side load and overhung moment** — that is a basic
  installation parameter, and not having it means you are not talking to
  application engineering

If two or more of those come up, that is the signal to open the **Kubota V3800**
conversation in parallel — which is why the engine bay is being designed to
accept both (`09-engine-selection.md`).
