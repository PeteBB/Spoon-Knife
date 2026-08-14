(*
    FB_AxisConditioning.st

    Turns one raw dual-channel joystick axis into a trustworthy, nicely-shaped
    command. Four jobs, in this order:

      1. Plausibility  - cross-check the redundant channels, latch a fault.
      2. Deadband      - kill center noise WITHOUT introducing a step.
      3. Expo          - fine control near center, full authority at the stops.
      4. Rate limit    - separate accel/decel so the machine cannot be snapped.

    Order matters. Deadband before expo, expo before rate limiting. Doing the
    rate limit first would make the shaped curve fight the limiter and produce
    a soft, laggy feel at small inputs.

    Call every scan of the task that owns this axis.
*)
FUNCTION_BLOCK FB_AxisConditioning
VAR_INPUT
    stRaw       : ST_RawAxis;   (* from HAL                                   *)
    rDeadband   : REAL := 0.07; (* fraction of half-travel                    *)
    rExpo       : REAL := 0.35; (* 0 = linear, 1 = pure cubic                 *)
    rRateUp     : REAL := 1.4;  (* command units/s, moving away from zero     *)
    rRateDown   : REAL := 2.5;  (* command units/s, moving toward zero        *)
    rDt         : REAL := 0.010;(* task period, s                             *)
    xEnable     : BOOL;         (* FALSE ramps output to zero at rRateDown    *)
    xResetFault : BOOL;         (* rising edge clears a latched fault         *)
END_VAR

VAR_OUTPUT
    rCmd        : REAL;         (* -1.0 .. +1.0, ready to mix                 *)
    xFault      : BOOL;         (* latched channel disagreement / open circuit*)
    xAtNeutral  : BOOL;         (* inside the neutral window, for interlocks  *)
END_VAR

VAR
    rSum        : REAL;
    rShaped     : REAL;
    rTarget     : REAL;
    rMag        : REAL;
    rSign       : REAL;
    rStep       : REAL;
    rFaultTimer : REAL;
    xResetPrev  : BOOL;
END_VAR

(* ---------------------------------------------------------------------------
   1. Plausibility.
   A single Hall element failing to a valid-looking voltage is the classic
   runaway failure on this class of machine. The two elements have opposite
   slopes, so their sum is constant across the whole travel; any departure
   means one of them is lying. Debounced so EMI does not shut the machine down,
   latched so an intermittent fault cannot self-clear under the operator.
--------------------------------------------------------------------------- *)
rSum := stRaw.rChA + stRaw.rChB;

IF NOT stRaw.xInRange OR ABS(rSum - C_AXIS_SUM_NOMINAL) > C_AXIS_SUM_TOL THEN
    rFaultTimer := rFaultTimer + rDt;
    IF rFaultTimer >= C_AXIS_FAULT_DEB_S THEN
        xFault := TRUE;
    END_IF;
ELSE
    rFaultTimer := 0.0;
END_IF;

IF xResetFault AND NOT xResetPrev AND stRaw.xInRange THEN
    xFault      := FALSE;
    rFaultTimer := 0.0;
END_IF;
xResetPrev := xResetFault;

(* ---------------------------------------------------------------------------
   2. Deadband with rescale.
   Naive deadband (clamp to zero inside the band, pass through outside) leaves
   a step at the band edge - the machine sits still, then lurches. Rescaling
   the remaining travel back to full range removes the step entirely.
--------------------------------------------------------------------------- *)
IF xFault OR NOT xEnable THEN
    rTarget := 0.0;
ELSE
    rMag := ABS(stRaw.rChA);
    IF stRaw.rChA >= 0.0 THEN rSign := 1.0; ELSE rSign := -1.0; END_IF;

    IF rMag <= rDeadband THEN
        rShaped := 0.0;
    ELSE
        rShaped := (rMag - rDeadband) / (1.0 - rDeadband);
        IF rShaped > 1.0 THEN rShaped := 1.0; END_IF;

        (* 3. Expo: blend linear and cubic. Cubic alone is too dead near
              center for grading work; the blend keeps usable low-speed
              resolution without making the operator hunt for the stops. *)
        rShaped := (1.0 - rExpo) * rShaped + rExpo * rShaped * rShaped * rShaped;
    END_IF;

    rTarget := rSign * rShaped;
END_IF;

(* ---------------------------------------------------------------------------
   4. Asymmetric rate limit.
   Accelerating is limited harder than decelerating. Letting the operator come
   off the stick faster than they can get on it is both safer and, oddly, makes
   the machine feel MORE responsive - the lag people complain about is almost
   always the deceleration edge.
--------------------------------------------------------------------------- *)
IF ABS(rTarget) > ABS(rCmd) AND (rTarget * rCmd) >= 0.0 THEN
    rStep := rRateUp * rDt;      (* magnitude increasing, same sign          *)
ELSE
    rStep := rRateDown * rDt;    (* returning to zero, or crossing over      *)
END_IF;

IF rTarget > rCmd + rStep THEN
    rCmd := rCmd + rStep;
ELSIF rTarget < rCmd - rStep THEN
    rCmd := rCmd - rStep;
ELSE
    rCmd := rTarget;
END_IF;

xAtNeutral := ABS(stRaw.rChA) <= C_NEUTRAL_WINDOW;
