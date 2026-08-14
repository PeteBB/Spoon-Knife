# Wireless Attachment Control — M18-Powered Module

> **It doesn't matter what machine. The attachment has the brain.**

A self-contained wireless control for hydraulic attachment functions. Powered by
a Milwaukee M18 pack, commanding the attachment's own DC stack valve, driven by
a transmitter that **clips onto the machine's existing joystick**. No wiring
into the machine. Works on any loader with auxiliary hydraulics.

That line above is the product, the architecture and the marketing position in
one sentence. Keep it. Everything in this folder is downstream of it, and any
proposal that makes it less true is a proposal to reject.

---

## 1. Why this is the right first product

It is not a detour from the track loader. **It is already part of the plan** —
`loader-control/docs/11-attachment-philosophy.md` describes exactly this as
Tier 2 of the attachment strategy. Building it now means:

| | |
|---|---|
| **Fundable** | Prototype cost is hundreds, not hundreds of thousands. You can build this around a job. |
| **Sellable immediately** | It does not depend on your machine existing. The addressable market is every skid steer and CTL already in the field. |
| **Proves the philosophy** | Machine as power plant, attachment owns its function — this product *is* that principle. |
| **Builds the asset that matters** | A customer list, a brand, and dealer relationships that exist before the machine ships. |
| **Not thrown away** | It becomes the Tier 2 offering for the loader later. Same product, bigger context. |

The big machine stays the goal. This is the thing that pays for it, and it is
made of the same ideas.

---

## 2. Competitive reality — read this first

**You are not first, and that is important to know before you spend anything.**

At least two products already do broadly this:

- **[Skid Sync U400](https://www.skid-sync.com/shop/p/u400-universal-remote-controller)** — universal wireless control box, 2–4 functions, internal battery, pre-paired handheld remote, no machine wiring
- **[Skid Steer Genius WACT](https://skidsteergenius.com/products/wireless-attachment-control-trigger-6-channel-skid-steer-genius)** — six-channel wireless receiver mounting next to the attachment's solenoids

This is **good news, not bad**. It means:

1. **The market is proven.** Someone else has already validated that operators
   will pay to avoid machine wiring. You are not gambling on demand.
2. **Your research is cheap and fast.** Buy a competitor's unit. Use it on a
   real job. The list of everything wrong with it is your product spec, and it
   costs a few hundred dollars and a weekend.

But it does mean you need genuine differentiation, not just a second version.

### The three differentiators you already have

**1. The M18 pack — this is the strongest one.**
Competitors use internal batteries. That means charging is a chore, a dead unit
means you are down, and the battery is proprietary. **Every contractor already
has four M18 packs in the truck, already charged.** A dead unit becomes a
five-second swap instead of an evening on a charger. That is a real, specific,
easily-explained advantage on a dealer floor.

**2. The joystick-clip transmitter — this is the one nobody has.**
Both competitors use a **handheld** remote. That means the operator is holding a
remote in one hand and a joystick in the other, or setting the remote down and
picking it up again. **Putting the buttons on the joystick the operator is
already gripping is simply better**, and it is the difference between a gadget
and a control.

Keep a handheld pendant as a *second* option for out-of-cab work — positioning a
grapple around a log, spotting a shear — but the clip is the headline.

**3. Open, 3D-printed adapters.**
One electronics pod, a growing catalogue of printed clamp shells for different
grips. **Publish the STLs.** It costs nothing, it means the product fits grips
you have never seen, and it is the same "publish the interface" instinct that
runs through the whole project. No competitor can easily follow, because their
business is moulded plastic.

### What to do this week

1. Buy a Skid Sync or WACT unit. Use it. Write down everything that annoys you.
2. Confirm what they charge, so you know what the market bears.
3. Check whether either has patents that read on the clip-on transmitter idea.
   That is a real question and worth an hour with a patent attorney before you
   invest, not after.

---

## 3. What it is, physically

```
   ┌─────────────────────────┐         ┌──────────────────────────────┐
   │  JOYSTICK CLIP          │  radio  │  ATTACHMENT MODULE           │
   │  ─────────────          │ ──────► │  ────────────────            │
   │  4–6 thumb buttons      │         │  M18 pack bay (sealed, lock) │
   │  Coin/rechargeable cell │         │  Buck 18V → 12V              │
   │  3D-printed clamp shell │         │  MCU + radio RX              │
   │  (interchangeable)      │         │  4–6 solenoid drivers        │
   └─────────────────────────┘         │  Deutsch DT to the valve     │
                                       └──────────────────────────────┘
                                                    │
                                       attachment's existing DC stack valve
                                                    │
                                       hydraulic power from the MACHINE
```

The machine supplies flow and pressure through the standard auxiliary couplers,
exactly as it always has. The module supplies only the *electrical control* of
the attachment's own valve. **Nothing connects to the machine electrically.**

**Scope: the module adds functions 2, 3 and 4.** The attachment's primary
function — open/close on a grapple — stays on the machine's own aux rocker,
untouched. The module selects which secondary function the machine's flow is
routed to, which means the operator's rocker is still doing the modulating and
**every function inherits proportional control for free.** See
`docs/00-module-design.md` §0 — this is the decision that makes the product
cheaper, simpler and better than driving everything from the module.

---

## 4. Documents

| | |
|---|---|
| `docs/00-module-design.md` | Full system map: power budget, radio, safety architecture, mechanical, development phases |
| `firmware/safety_core.c` | Portable safety core — link watchdog, neutral-before-enable, peak-and-hold driver |

---

## 5. The one hard requirement

**The attachment's valve must be spring-centred.**

If power is lost — flat pack, dropped radio link, failed module — de-energising
the coils has to return the valve to neutral and stop the function. A detented
or hydraulically-latched valve will keep running with no power and no control,
which is exactly the failure this product must never cause.

This goes in the installation instructions in bold, and the product should
refuse to be sold as compatible with detented valves.
