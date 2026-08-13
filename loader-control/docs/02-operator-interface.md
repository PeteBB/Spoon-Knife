# Operator Interface — Joysticks, Buttons and Function Mapping

## 1. Axis assignment (ISO pattern)

| Control | Axis | Function |
|---|---|---|
| **Left grip** | fore / aft | Propel forward / reverse |
| | left / right | Steer |
| **Right grip** | fore / aft | Boom lower / raise |
| | left / right | Bucket dump / curl |

Ship ISO as the default and **make H-pattern a display-selectable option**.
It costs you one `CASE` statement — the mixing math is already isolated in
`FB_DriveMixer` — and it removes a real objection from operators who came up on
older machines. Competitors charge for this or do not offer it.

---

## 2. Button layout

Nothing here is hard-wired in the code. Every entry below is a **default
binding** in a table stored in non-volatile memory, editable from the display
and overridable per attachment. See section 4.

### Left grip — travel and machine

| Control | Type | Default function |
|---|---|---|
| Thumb top | Momentary | Two-speed toggle (low ⇄ high) |
| Thumb front | Momentary | Horn |
| Index trigger | Momentary | Creep mode, hold-to-engage |
| Rocker up / down | Momentary ×2 | Engine speed increment / decrement |
| Toggle | 2-position | Work lights |

### Right grip — loader and attachment

| Control | Type | Default function |
|---|---|---|
| **Thumb rocker** | **Proportional, bidirectional** | **Aux 1 flow, A and B** |
| Index trigger | Momentary | Aux detent latch / release |
| Thumb top | Momentary | Return to dig |
| Thumb front | Momentary | Float (boom) |
| Button 4 | Momentary | Aux 2 (on/off secondary circuit) |
| Toggle | 2-position | High flow enable |

**The proportional thumb rocker is non-negotiable.** On/off aux is the loudest
complaint operators have about machines in this class — it makes a grapple snap
shut and a mulcher impossible to feather. Proportional aux with a tunable ramp
is a cheap, immediately-obvious win on a demo ride.

---

## 3. Press semantics

`FB_ButtonInput` decodes four gestures from every momentary button, so one
button can carry more than one function without crowding the grip:

| Gesture | Timing | Typical use |
|---|---|---|
| **Short press** | < 400 ms | Primary action — toggle, trigger, latch |
| **Long press** | ≥ 800 ms held | Secondary — *teach* the current position, enter setup |
| **Double tap** | 2 within 400 ms | Tertiary — recall, reset to default |
| **Hold** | continuous while down | Momentary functions — creep, horn |

The pattern that pays for itself: **short press recalls, long press teaches.**
Return-to-dig short-presses to run the bucket to the stored angle, long-presses
to store the angle the bucket is at right now. Operators discover this in
thirty seconds and it makes the machine feel like it was built for them rather
than for a spec sheet.

---

## 4. Configurable mapping — the differentiator

Buttons emit **events**; events are bound to **functions** through a table.
Neither side knows about the other.

```
  physical button  ──►  FB_ButtonInput  ──►  event  ──┐
                                                      ├──►  binding table  ──►  function
  attachment profile  ─────────────────────────────────┘         (in NVM)
```

Why this is worth building properly:

1. **Operators re-map to taste.** The single most common complaint about any
   machine's controls is "the buttons are in the wrong place." Nobody in this
   class lets the customer fix that. You can, for free.
2. **Attachments re-map themselves.** Plug in a grapple and the trigger becomes
   clamp; plug in a mulcher and it becomes rotor engage with a soft-start ramp.
   The operator never opens a menu.
3. **Dealers demo it.** A salesperson who can hand the grips to a prospect and
   say "put the buttons where you want them" has a story nobody else has.
4. **It de-risks your own launch.** If a default binding turns out to be wrong
   after fifty machines are in the field, it is a settings change, not a
   software recall.

Guard rails: safety-relevant functions (park brake, engine stop, aux disable)
are **not** bindable — they are fixed in code and rejected by the editor. A
customer must not be able to map "engine stop" onto a button they will hit with
their thumb while grading.

---

## 5. Aux hydraulic behaviour

The detail here is what separates a machine operators like from one they
tolerate.

**Proportional flow.** Rocker position maps through deadband → expo → ramp to
aux flow, exactly as the main axes do, with its own ramp rate because
attachments have very different inertia. A hydraulic breaker wants a fast ramp;
a mulcher rotor wants a slow one or you shock the drive.

**Detent latch.** Trigger press latches the current rocker command so the
operator can let go and run the attachment hands-free. Release on: trigger
press again, rocker pushed past threshold in the *opposite* direction, operator
out of seat, engine stop, aux over-pressure, or attachment fault. While
latched, the rocker still **modulates** — most machines force you to unlatch to
change flow, which is needlessly annoying.

**Soft start out of detent.** Ramp to the latched value rather than stepping to
it. A cold planer drum stepping to full flow is a shock load through the whole
attachment driveline.

**High flow.** Interlocked to: attachment declares support, engine at
sufficient RPM, oil above minimum temperature. Refusing high flow on cold oil
prevents a class of attachment motor failure that customers will otherwise
blame on you.

**Pressure protection.** Watch aux circuit pressure. Sustained relief means
something is stalled or jammed — derate flow and put a plain-language message
on the display instead of cooking the oil and letting the operator wonder why
the machine got slow.

---

## 6. Loader function behaviour

**Self-level, both directions.** Bucket angle relative to ground held constant
as the boom moves. Feed-forward from measured boom velocity does the work; a
slow PI trim on angle error cleans up the residual. Most competitors level on
raise only — levelling on lower as well is noticeable within one load cycle and
costs nothing extra given you already have both angle sensors.

**Return to dig / return to carry.** Short press runs the bucket to a stored
angle; long press stores the current angle. Two independent stored positions.

**Boom height limit.** Operator-settable maximum boom height, taught the same
way. Anyone who has worked under a door header or inside a barn will pay for
this feature by itself.

**Float.** Boom section to float so the bucket follows ground contour for
back-dragging. Inhibited above a low boom height so an operator cannot drop the
boom from height by fumbling a button.

**Shake.** Double-tap dump to oscillate the tilt section briefly and shed
sticky material. Trivial to implement, and it delights people.
