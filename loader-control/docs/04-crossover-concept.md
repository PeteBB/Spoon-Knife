# The Crossover Concept — Crawler Loader Capability in a CTL Package

## 1. The thesis, stated precisely

Compact track loaders are excellent at *handling* and mediocre at *digging*.
Crawler loaders were the opposite. Every operator who has tried to fill a bucket
in hard material with a CTL knows the failure mode: the tracks spin, the bucket
does not fill, and the operator burns rubber they will pay for later.

The gap is real and it is unserved. The question is what to do about it.

## 2. The trap to avoid

Crawler loaders did not die of neglect. They were squeezed out from both sides —
excavators took the digging, skid steers and CTLs took the versatility — and the
economics that killed them have not changed. A crossover that answers the
capability gap **with mass** walks straight back into the reasons the class
died:

- **Transportability.** A CTL under roughly 10,000 lb goes on a standard
  equipment trailer behind a three-quarter-ton pickup. Above that you are into
  lowboy and CDL territory, and you have deleted the single biggest practical
  advantage of the class for the contractor market.
- **Ground pressure.** Weight is what CTL customers are buying *away* from.
  Landscapers and site contractors chose these machines to stay off lawns and
  soft ground.
- **Attachment ecosystem.** The universal quick-attach plate and the attachment
  catalogue are most of the value proposition. A heavier, more specialized
  machine erodes it.
- **Cost per hour.** Undercarriage is already the dominant running cost on a
  CTL. More weight on rubber tracks makes that worse, not better.

So the concept only wins if it delivers crawler-loader *capability* without
crawler-loader *mass*.

## 3. Why that is achievable — and why it is a controls project

Here is the thing: **most of what made a crawler loader dig well was not weight.
It was torque management, and it was mechanical because it had to be in 1985.**

| Crawler loader had | Because | Modern equivalent |
|---|---|---|
| Torque converter multiplying torque as it stalled into the pile | It was the only way to do it mechanically | Pressure-based displacement control — pure software |
| Differential steering (Cat 953C and up) that turned without dumping tractive effort | A cross-shaft and a steer motor | Steering strategy in the mixer — pure software |
| Powershift with an operator who modulated the decel pedal | Hand throttle plus foot decel | Decel pedal input plus torque-based propel — cheap hardware, mostly software |
| Weight and a deep undercarriage to resist slip | Nothing else limited rimpull | Rimpull limiting and slip control — pure software |
| An experienced operator managing the crowd cycle by feel | No automation existed | Dig assist — pure software |

Read that right-hand column again. **Every mechanical advantage the crawler
loader had is now available as a control strategy, at a few hundred dollars of
sensors instead of a thousand pounds of iron.** That is the entire thesis of the
machine, and it is why the controls being your limiting factor is actually the
good news — it is the only thing standing between you and a machine that digs
like a 953 and trailers like a CTL.

## 4. The feature set, ranked

### Tier 1 — the ones that make the machine

**1. Rimpull limiting (`FB_TractiveControl`)**
Operator-settable ceiling on tractive effort, implemented as a limit on propel
loop pressure. Counter-intuitive and transformative: by *refusing* to push
harder than the tracks can grip, full engine power stays available to the work
hydraulics for curl and lift. The bucket fills instead of the tracks spinning.

Cat proved this concept on wheel loaders with rimpull control and the impeller
clutch. **Nobody has put it on a CTL**, and the CTL is where it matters most,
because on rubber tracks slip is not just lost time — it is the machine's single
largest running cost being converted into smoke.

This one feature is worth building the machine around. It is also the easiest
thing in this document to demonstrate to a customer: run your machine and a
competitor's into the same pile of bank-run gravel and let them watch.

**2. Effort-preserving steering (`FB_DriveMixer`, crawler mode)**
A skid-steer turn works by *slowing one track* — it throws away tractive effort
to change direction, which is exactly wrong when you are loaded and in the cut.
Differential steering on a crawler loader *transferred* effort instead, so the
machine kept pushing through the turn.

On a two-pump hydrostat you cannot transfer power across the axle mechanically,
but you can choose what to sacrifice when the command saturates:

- **Skid mode** — preserve the commanded turn *radius*, sacrifice forward speed.
  Correct for tight quarters and precision work. This is what every machine in
  the class does, all the time.
- **Crawler mode** — preserve forward speed and yaw rate, widen the radius.
  Correct in the pile, on grade, and under load.

Nobody offers both. Making it a blend on a single knob, defaulting by work mode,
is a genuinely novel control and it costs one function block.

**3. Slip control**
Two track speed sensors plus an IMU. If the tracks are turning and the machine
is not accelerating, it is slipping — derate before the rubber goes. Sell it as
undercarriage life, which is the number every CTL owner tracks.

### Tier 2 — strong differentiators

**4. Dig assist.** Automated crowd cycle: drive into the pile, and the
controller coordinates boom raise and bucket curl against measured propel
pressure to fill the bucket without stalling or spinning. Big wheel loaders have
had this for years. No CTL has it. This is what makes a green operator
productive on day one, which is a rental-fleet and labour-shortage argument as
much as a performance one.

**5. Grade hold / cross-slope.** A ~$200 IMU gives pitch and roll. Hold a
cross-slope automatically while back-dragging or spreading. Crawler loaders were
the poor man's dozer; this is how you reclaim that role without a blade.

**6. Decel pedal.** Old crawler loaders and dozers have one and operators love
it — momentarily drop engine speed for precision without touching the throttle
setting. Almost extinct in this class. A pedal, an input, and about forty lines
of code.

**7. Boom down-pressure.** Commanded down-force rather than float, so the bucket
can be driven into the ground for back-dragging and cutting. Most CTLs offer
float or nothing.

**8. Payload weighing.** Bucket weight from lift cylinder pressure and boom
angle, with running totals per load and per day. Wheel loaders have it, CTLs do
not, and it costs two sensors you are already fitting.

### Tier 3 — heritage details worth keeping

- Rear auxiliary circuit and drawbar for a ripper — crawler loaders earned their
  keep on the back end too
- High seating position and genuine over-the-front bucket visibility
- Four-in-one bucket as a first-class citizen in the attachment profile system,
  not an afterthought

## 5. What this means for the machine spec

The controls strategy above lets you make choices that would otherwise be
contradictory:

- **Stay under the trailer weight limit.** You are buying digging capability
  with software, not ballast.
- **Spend the weight budget on the undercarriage, not the body.** A stiffer,
  deeper undercarriage with better track tension control is where crawler
  heritage genuinely belongs, and rimpull limiting protects the investment.
- **Keep the universal quick-attach plate.** Do not trade the attachment
  ecosystem for specialization.
- **Position it as the CTL that can actually dig**, not as a small crawler
  loader. The former is an unserved segment; the latter is a dead one.

## 6. Sensors this concept adds

Beyond the inventory in `00-architecture.md`:

| Sensor | Purpose | Note |
|---|---|---|
| Propel loop pressure, left and right | Rimpull limiting, dig assist load sensing | The enabling sensor for tier 1. Non-negotiable. |
| 6-axis IMU | Slip detection, grade hold, cross-slope | Cheap. Mount it on the frame, isolated from engine vibration. |
| Lift cylinder pressure | Payload weighing, down-pressure control | |
| Decel pedal position | Decel function | |

That is roughly four hundred dollars of sensing standing between a conventional
CTL and everything in section 4.

## 7. Build order

1. `FB_TractiveControl` — rimpull limit and slip control **(built)**
2. `FB_DriveMixer` crawler/skid steering blend **(built)**
3. Dig assist — needs propel pressure data from a real machine first
4. Grade hold and cross-slope — needs the IMU mounted and characterised
5. Payload weighing — needs a calibration campaign with known loads
6. Decel pedal, down-pressure — trivial once the hardware is fitted

Items 3–5 are all gated on the same thing: a running prototype producing real
sensor data. Everything before that gate, I can write now.
