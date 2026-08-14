# Compact Track Loader — Machine Control System Architecture

Working design document. Platform-neutral IEC 61131-3 (Structured Text) with a thin
hardware abstraction layer, so the same control logic ports across CODESYS-based
controllers (IFM CR-series, TTControl HY-TTC, Epec) with a rewrite of only the HAL.

---

## 1. What the controller actually does

On a modern CTL the PLC is not "the computer that runs the machine" — it is a
translator sitting between three worlds:

```
  OPERATOR                 CONTROLLER                    MACHINE
  ────────                 ──────────                    ───────
  Joysticks (Hall)  ──►  ┌──────────────────┐  ──►  Propel pump EDC coils (mA)
  Thumb rockers     ──►  │  1. Acquire       │  ──►  Loader valve sections (mA)
  Keypad / display  ──►  │  2. Condition     │  ──►  Aux flow section (mA)
  Seat + seat bar   ──►  │  3. Arbitrate     │  ──►  2-speed / ride-control sols
                         │  4. Protect       │
  Engine ECU (J1939)──►  │  5. Command       │  ──►  Engine speed request (J1939)
  Pressure sensors  ──►  │  6. Diagnose      │  ──►  Display / fault codes
  Speed sensors     ──►  └──────────────────┘  ──►  Telematics
  Temp sensors      ──►
```

Steps 2 and 4 are where machines are won and lost. Step 1, 3, 5, 6 are
straightforward engineering. **The feel of the machine lives almost entirely in
the conditioning and arbitration math**, which is exactly the part that is
software and therefore the part you can beat the competition on without
out-spending them on hardware.

---

## 2. Honest difficulty assessment

| Layer | Difficulty | Who does it |
|---|---|---|
| Control logic (mixing, ramps, curves, modes, aux, anti-stall, diagnostics) | **Moderate.** Well-understood, and I can write essentially all of it. | Me + you |
| CAN / J1939 integration with the engine ECU | **Moderate.** Mostly transcription from the engine supplier's spec. | Me + engine vendor docs |
| HMI / display application | **Moderate.** Tedious, not hard. | Me + you |
| Hydraulic calibration (pump gain, coil thresholds, valve deadbands, hysteresis) | **Hard, and unavoidably empirical.** Cannot be derived on paper. Needs a machine, a flow meter, and iteration. | You, on a real machine |
| Functional safety chain to ISO 13849 PL d | **Hard, and it is a process problem, not a coding problem.** | Certified hardware + a documented V-model + third-party review |
| Certification for sale (engine emissions, EMC, CE/UKCA, product liability) | **Hard. Money and calendar time, not cleverness.** | Compliance consultant |

So: the software is genuinely the *easy* third of this, and it is the third
where the differentiation lives. That is good news for you. The limiting factor
you named — controls — is the most tractable part of the problem.

### The one thing that must not be in my code

**The drive-enable / interlock chain must not depend on application software for
its safety rating.** Operator out of the seat, seat bar up, or park brake
commanded → propel and loader function must be removed by a path that is rated
independently of the application program. In practice that means a certified
safety controller or a hardwired dual-channel relay chain that cuts coil power,
with the PLC's software interlock running *in parallel* as the functional (not
safety) layer.

Everything in `src/st/` is the functional layer. `FB_InterlockLogic` mirrors the
hardware chain so the machine behaves consistently and can report *why* it is
inhibited — it is not the thing that keeps the machine from running someone over.

Relevant standards to have a compliance person confirm and scope:
ISO 13849-1 (safety-related control system performance levels), ISO 15998
(electronic machine control systems for earth-moving machinery), ISO 20474
(earth-moving machinery safety — check which part covers skid-steer/CTL for
your market), ISO 14990 (electrical safety), SAE J1939 (CAN), plus EN 474 for
Europe. I have flagged the ones I am confident are in scope; treat the exact
part numbers as something to verify rather than as citations.

---

## 3. Controller hardware shortlist

| Platform | Language | Notes |
|---|---|---|
| **IFM CR7132 / CR711S** | CODESYS 3.5 (IEC 61131-3) | CR711S is SIL2/PLd certified. Big I/O count, good current-controlled outputs, cheap. Best default. |
| **TTControl HY-TTC 500** | CODESYS or C | Highest safety pedigree (PLd/SIL2 out of the box), used by serious OEMs. Expensive. |
| **Danfoss Plus+1 MC050** | Plus+1 GUIDE (graphical) | Excellent if you are also buying Danfoss pumps/valves — the ecosystem integration is real. GUIDE is not IEC 61131-3, so code does not port. |
| **Parker IQAN MD4 + MC4x** | IQANdesign | Fastest to a working prototype, superb display tooling, weakest for custom math. |
| **Epec 5050** | CODESYS 3.5 | Solid middle option, strong in forestry/ag. |

**Recommendation: prototype on IFM CR-series with CODESYS.** IEC 61131-3 means
the logic is portable, the current-controlled PWM outputs drive proportional
coils directly without extra amplifiers, and if you later need the safety rating
you move to the CR711S with the same toolchain.

---

## 4. Signal inventory (first pass)

### Analog / frequency inputs
| Signal | Type | Purpose |
|---|---|---|
| Left joystick X, Y | Dual-redundant ratiometric Hall (2 channels each) | Propel |
| Right joystick X, Y | Dual-redundant ratiometric Hall | Loader lift / tilt |
| Aux proportional rockers (L, R) | Ratiometric | Aux flow both directions |
| Left / right track speed | Hall pickup on motor or sprocket | Slip detection, true ground speed, 2-speed shift |
| Charge pressure | 0.5–4.5 V | Hydrostat health |
| Loader circuit pressure | 0.5–4.5 V | Load sensing, RTD, shake |
| Aux circuit pressure A/B | 0.5–4.5 V | Attachment protection, relief detect |
| Hydraulic oil temp | Thermistor | Derate, warm-up strategy |
| Lift arm angle | Rotary or string pot | Self-level, RTD, height limit |
| Tilt / bucket angle | Rotary or string pot | Self-level, return-to-carry |
| Fuel level | Resistive | Display |

Joystick axes are **dual-channel with cross-checking** — a single-channel Hall
sensor failing high is a runaway. This is non-negotiable and it is cheap.

### Digital inputs
Seat switch, seat bar, park brake request, 2-speed request, creep enable,
aux detent request, high-flow request, float request, RTD set/recall, horn,
door/canopy, filter restriction, air filter, coolant level, hydraulic level.

### Outputs

Superseded in part by the CAN-centric decision in `01-hardware-selection.md`:
the loader and aux sections are commanded over CAN through PVED-CC actuators on
the PVG 32 bank, not by controller current outputs. Only the propel pumps and
the simple on/off solenoids remain hard-wired.

| Output | Type |
|---|---|
| Propel pump fwd/rev EDC coils (×4: L-fwd, L-rev, R-fwd, R-rev) | Current-controlled PWM w/ dither |
| Lift raise / lower | CAN — PVG 32 section |
| Tilt back / dump | CAN — PVG 32 section |
| Aux A / B | CAN — PVG 32 section |
| High-flow enable | Digital |
| 2-speed shift | Digital |
| Ride control | Digital |
| Park brake release | Digital, safety-relevant |
| Float | CAN — PVG 32 section, 4th position |

### J1939 (engine)
Consume: EEC1 (engine speed, torque mode, driver demand torque), EEC2
(accelerator position, load at current speed), ET1 (coolant temp), fluid level/
pressure, DM1 (active DTCs), aftertreatment status.
Transmit: TSC1 (engine speed/torque request) for auto-idle, throttle, and
anti-stall assist.

Exact PGN/SPN mapping comes from the engine supplier's application manual —
Yanmar/Kubota/Perkins each deviate from generic J1939 in small ways.

---

## 5. Execution model

Three tasks, priority high → low:

| Task | Period | Contents |
|---|---|---|
| `T_Fast` | 10 ms | Joystick acquisition + plausibility, propel mixing, pump current output, anti-stall, interlocks |
| `T_Med` | 50 ms | Loader/aux control, self-level, RTD, 2-speed, ride control, J1939 TX |
| `T_Slow` | 200 ms | Diagnostics, fault logging, display update, telematics, hour meters |

10 ms on the propel loop is what makes a machine feel connected rather than
rubbery. Do not economise here.

---

## 6. Where you beat the competition

Ranked by (customer-perceived value) ÷ (cost to implement). The top four are
pure software and cost you only engineering time:

1. **Per-operator response profiles.** Store 3–5 named profiles: joystick expo,
   accel/decel ramps, max speed, aux ramp, steering aggressiveness. A rental
   fleet operator and an owner-operator finish grader want opposite machines.
   Almost nobody does this well, and it converts demo rides into sales.
2. **True anti-stall with correct priority.** When the engine droops, cut
   *propel* first and preserve *work hydraulics*. Most machines derate
   everything and the operator loses the cut. Done right this feels like the
   machine has more power than the spec sheet says.
3. **Attachment auto-recognition with stored profiles.** ID chip or CAN node on
   the attachment → controller loads flow limit, pressure limit, ramp rates,
   detent behaviour, and the correct HMI screen automatically. This is the
   ecosystem moat; it is also what locks customers into *your* attachments.
4. **Precision / creep mode decoupled from engine speed.** Cold planers,
   mulchers and trenchers need full engine RPM and 0.3 mph ground speed
   simultaneously. Scale propel independent of throttle.
5. **Electronic self-level on both raise and lower.** Most competitors level on
   raise only.
6. **Return-to-dig / return-to-carry with operator-taught positions**, not
   factory-fixed detents.
7. **Auto ride control** engaging above a speed threshold and dropping out
   automatically for loading.
8. **Slip control** using the two track speed sensors — detect and limit spin,
   protects the undercarriage, which is the CTL's biggest running cost.
9. **Real diagnostics.** Fault codes with plain-language text, freeze-frame
   data, and a service screen that shows live I/O. Dealers will love you.
10. **Grade-control-ready CAN interface** so Trimble/Topcon integrate without a
    harness kit.

---

## 7. Development order

1. **Bench rig first.** Controller + joysticks + a load bank or a few
   proportional coils + a CAN engine simulator. Every function block in
   `src/st/` gets validated here before it touches iron.
2. Propel loop on a test stand with real pumps.
3. Loader/aux on the machine.
4. Calibration campaign (this is the long pole).
5. Anti-stall and modes tuning.
6. Safety chain design + third-party review.
7. Durability, EMC, environmental.

Steps 1–3 and 5 I can do most of the work on. Step 4 is you and a machine.

---

## 8. Repository layout

```
loader-control/
  docs/
    00-architecture.md          this file
    01-hardware-selection.md    controller, grips, valves, engine, bus layout
    02-operator-interface.md    axis assignment, button map, function behaviour
    03-sourcing-and-supply.md   purchase points, second sourcing, ramp strategy
    04-crossover-concept.md     crawler-loader heritage features, ranked
    05-rear-implement-architecture.md  3-point hitch, PTO, engine orientation
    06-frame-balance-and-stability.md  load cases, ballast, load moment
    07-dozing-and-drawbar.md    capacity/pull trade, blade mounting, grade control
    08-dozer-attachment-integration.md  push link, load-path modes
    09-engine-selection.md      Cummins B4.5, air-cooled blocker, reversing fan
    10-cummins-supplier-questions.md  engine supplier call checklist
  src/
    st/                         IEC 61131-3 Structured Text, portable
      GVL_Types.st              enums, structs, tuning constants
      GVL_OperatorMap.st        button ids, function enum, default bindings
      FB_AxisConditioning.st    deadband, expo, rate limiting, plausibility
      FB_DriveMixer.st          propel + steer -> left/right track command
      FB_ProportionalOut.st     normalized command -> coil current
      FB_AntiStall.st           engine droop -> propel derate
      FB_TractiveControl.st     rimpull ceiling, slip control, ground speed
      FB_PtoControl.st          modulated clutch engagement, PTO supervision
      FB_HitchControl.st        position/draft/slip-referenced hitch control
      FB_HeadlandSequence.st    two-press headland turn sequencing
      FB_LoadMoment.st          payload weighing, stability margin, raise limit
      FB_BladeControl.st        cross-slope hold, blade load control
      FB_DozerMode.st           push-link load path, rimpull scheduling
      FB_CoolingFan.st          variable-speed reversing fan, cooler purge
      FB_ButtonInput.st         debounce, short/long/double/hold gestures
      FB_FunctionDispatch.st    binding table -> function requests
      FB_LoaderControl.st       self-level, return-to-dig, float, height limit
      FB_AuxControl.st          proportional aux, detent, high flow, protection
      PRG_Propel.st             10 ms task
      PRG_Loader.st             50 ms task
      PRG_Rear.st               50 ms task - hitch, PTO, headland
    hal/                        platform-specific I/O binding (per controller)
```
