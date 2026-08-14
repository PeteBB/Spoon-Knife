# Engine Selection — Cummins and the Air-Cooled Question

Both of your preferences have real logic behind them. One of them survives; the
other runs into a wall that has nothing to do with price.

---

## 1. The air-cooled Deutz: blocked by emissions, not cost

**Deutz's air-cooled families remain in production only at Tier 0 through Tier
3.** The 912 and 914 families are still built, but at those emission levels;
Stage V and Tier 4 Final are served by the **liquid-cooled TCD series**. Several
air-cooled models have been discontinued outright.

That is a hard stop for a machine you intend to sell new into the US or EU. Not
a price problem, not a sourcing problem — an air-cooled Deutz at ~100 hp that
meets Tier 4 Final / Stage V does not appear to exist to buy.

The reason is structural rather than commercial. Modern emissions control needs
**precise thermal management**: EGR wants a cooler, aftertreatment wants
controlled exhaust temperature windows, and combustion temperature has to be
held tightly enough to trade NOx against particulates. Air cooling gives you far
less authority over any of that. It is why essentially the whole industry moved
to liquid cooling above the small-engine thresholds.

### But your underlying instinct is correct, and it deserves an answer

The real reason air-cooled Deutz earned its reputation in agriculture is not
nostalgia — it is that **there is no radiator core to plug.** Chaff, dust, seed
and leaf matter pack a cooler stack solid, the machine overheats, and someone
spends twenty minutes with an air hose every few hours. Anyone who has mowed or
worked in crop residue knows exactly this pain.

That problem is real and it will absolutely bite this machine. **The modern
answer is a variable-speed reversing hydraulic fan** (§4), which is a control
feature, and which I have built.

---

## 2. The Cummins: right family, wrong displacement

The **B3.3 runs 60–85 hp**, and its Tier 4 Final version was specifically
developed with a particulate-filter-only aftertreatment for compact equipment
**rated below 75 hp**. That is well under the 95–110 hp this machine needs once
the PTO is accounted for.

**The engine you want is the B4.5.** Available in Stage V and Tier 4 Final, and
rated up to ~173 hp in the QSB4.5 form.

That is more than you need, and that is the point:

> Running a 173 hp-capable engine at 100–110 hp means it lives its whole life
> well inside its envelope. Big torque reserve for PTO shock loads, low thermal
> and mechanical stress, long life, and headroom to grow the machine later
> without a new engine programme.

For a machine whose whole pitch is "instinctively powerful by design," a
comfortably de-rated engine is exactly right. It also strengthens the anti-stall
and rimpull strategy — an engine with reserve droops less, so the controller
intervenes less often and the machine feels stronger still.

### The badge is worth something, and that is not irrational

"Cummins powered" genuinely sells machines to farmers. Parts availability is
everywhere, every rural mechanic has worked on one, and the name buys trust a
new OEM has not yet earned. For a startup selling an unfamiliar machine, that
borrowed credibility is a real asset. Do not let anyone talk you out of it as
mere marketing.

### The thing to check before committing

**Supplier support model at your volume.** Kubota and Yanmar are structured to
support low-volume OEMs — application engineering, small MOQs, patient
distributors. Cummins is structured around large accounts, and its off-highway
OEM support at twenty machines a year may be thinner and its minimums higher.

Ask directly, early, and in these terms:

- What is the minimum annual volume for an OEM account?
- Who provides application engineering — Cummins, or the distributor?
- What is the lead time and allocation policy at our volume?
- Can we get the **J1939 interface specification** in writing before commitment?

That last one is not negotiable regardless of supplier — the anti-stall,
throttle and PTO code all depend on it.

**Keep Kubota V3800 as the qualified alternate.** Same power class, better
low-volume support, and per `03-sourcing-and-supply.md` the engine is the single
hardest thing on the machine to second-source. Having the alternate designed in
is worth the effort even if you never use it.

---

## 3. Cooling package — bigger than you think

A ~110 hp Tier 4 Final engine in a machine with a hydrostat, a PTO and a full
work hydraulic circuit needs a serious cooler stack:

- Radiator
- Charge air cooler
- Hydraulic oil cooler — **sized for hydrostatic work, which is a lot of heat**
- Fuel cooler
- Plus the thermal load of the DPF/SCR aftertreatment

That stack has to fit around a longitudinal engine that also has a PTO shaft
coming out the back, in a machine you are keeping physically compact. **Lay the
cooling package out early**, alongside the engine bay, not after the frame is
designed. Cooling is the most common thing to underestimate on a first machine,
and the symptom — derating in hot weather under load — shows up in front of
customers.

---

## 4. The reversing fan: the modern answer to what air-cooling solved

`FB_CoolingFan` (built) drives a **variable-speed, bidirectional hydraulic fan**:

**Variable speed** — fan demand is the maximum across coolant, hydraulic oil and
charge air temperature, each on its own curve. The fan spins only as fast as the
hottest circuit requires.

| Benefit | Why it matters |
|---|---|
| **Fuel** | A fixed fan runs at full power all day. A variable one usually does not. |
| **Noise** | The cooling fan is typically the dominant noise source on this class of machine. Operators notice immediately. |
| **Warm-up** | Fan held at minimum until the engine is warm — faster warm-up, and important for the cold-oil high-flow interlock in `FB_AuxControl`. |

**Automatic reversing** — periodically the fan spins down, stops, runs backwards
for a few seconds to blow the cooler pack clear, then resumes. This is standard
practice on combines and foragers and it directly solves the chaff-plugging
problem that made air-cooled Deutz attractive in the first place.

Two details in the implementation that matter:

1. **Dwell at zero between direction changes.** Reversing a spinning fan without
   letting it stop shock-loads the motor and its drive. The state machine spins
   down, waits, then reverses.
2. **Reverse is inhibited when anything is genuinely hot.** Purging is
   housekeeping; it must never take cooling away from a machine that is already
   struggling. If temps are high the cycle is deferred until they are not.

An operator button also triggers the cycle on demand — useful the moment they
notice they are working in something dusty, rather than waiting for the timer.

**Hardware note:** this needs a bidirectional fan motor and a valve capable of
reversing it. That is a real cost line, not free, and it should go into the
hydraulic schematic now rather than being retrofitted. Given what it replaces —
the reason you wanted air-cooling — it is the right money to spend.
