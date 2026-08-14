(*
    FB_DriveMixer.st

    Propel + steer  ->  left track / right track command.

    This block is the single biggest contributor to how the machine feels, and
    on this machine it also carries the crossover concept: it can behave like a
    skid steer or like a differential-steer crawler loader, on a blend.

    ---------------------------------------------------------------------------
    THE CROSSOVER IDEA

    A skid-steer turn works by SLOWING ONE TRACK. That throws tractive effort
    away in order to change direction - which is exactly the wrong trade when
    you are loaded and in the cut. It is why a CTL washes out of a pile the
    moment the operator asks for any steering correction.

    Differential steering on a crawler loader TRANSFERRED effort across the
    axle instead of discarding it, so the machine kept pushing through the
    turn. We cannot transfer power mechanically across two independent closed
    circuits, but we can choose what to give up when the command saturates:

      SKID mode    - preserve the commanded turn RADIUS, sacrifice speed.
                     Correct in tight quarters and for precision work.
      CRAWLER mode - preserve forward SPEED and yaw rate, widen the radius.
                     Correct in the pile, on grade, and under load.

    Turn radius on a tracked machine is (W/2)*(vL+vR)/(vL-vR), so preserving
    the RATIO of the two track speeds preserves the radius, and preserving the
    DIFFERENCE preserves the yaw rate. The two modes are exactly those two
    choices, and rSteerPriority blends between them.

    Every machine in this class does skid, always. Offering both, on a knob
    that defaults by work mode, is the novel control.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_DriveMixer
VAR_INPUT
    rPropel        : REAL;  (* -1..+1, conditioned fore/aft                   *)
    rSteer         : REAL;  (* -1..+1, conditioned left/right, + = right turn *)
    rSpeedScale    : REAL := 1.0;  (* mode/creep top-speed clamp, 0..1        *)
    rDerate        : REAL := 1.0;  (* anti-stall / thermal multiplier, 0..1   *)
    rSteerGainAtTop: REAL := 0.45; (* steering authority at full propel, 0..1 *)

    (* 1.0 = pure skid (preserve radius) .. 0.0 = pure crawler (preserve
       speed). Set by work mode, overridable by the operator. *)
    rSteerPriority : REAL := 1.0;

    (* Floor on delivered steering in crawler mode. Without this, crawler mode
       at full propel has no headroom left to speed the outside track up and
       the machine simply refuses to turn - correct arithmetic, alarming
       machine. This guarantees the operator always gets SOME turn. *)
    rMinSteerAuth  : REAL := 0.35;
END_VAR

VAR_OUTPUT
    rLeft          : REAL;  (* -1..+1 to left pump                            *)
    rRight         : REAL;  (* -1..+1 to right pump                           *)
    xSaturated     : BOOL;  (* diagnostics: the mix hit a limit               *)
END_VAR

VAR
    rP             : REAL;
    rSteerGain     : REAL;
    rSteerEff      : REAL;
    rPeak          : REAL;
    rScale         : REAL;
    rLimit         : REAL;
    rPrio          : REAL;

    (* skid resolution *)
    rSkidL         : REAL;
    rSkidR         : REAL;
    (* crawler resolution *)
    rCrawL         : REAL;
    rCrawR         : REAL;
    rHeadroom      : REAL;
    rSteerReq      : REAL;
    rSteerLim      : REAL;
    rPcraw         : REAL;
END_VAR

(* --- sanitise inputs ----------------------------------------------------- *)
rP := rPropel;
IF rP >  1.0 THEN rP :=  1.0; END_IF;
IF rP < -1.0 THEN rP := -1.0; END_IF;

rPrio := rSteerPriority;
IF rPrio < 0.0 THEN rPrio := 0.0; END_IF;
IF rPrio > 1.0 THEN rPrio := 1.0; END_IF;

(* --- schedule steering authority against travel speed -------------------- *)
(* At rP = 0 the gain is 1.0 (full counter-rotation).
   At |rP| = 1 the gain is rSteerGainAtTop. Linear in between: a curve here
   sounds clever but operators read linear as "honest". *)
rSteerGain := 1.0 - (1.0 - rSteerGainAtTop) * ABS(rP);
rSteerEff  := rSteer * rSteerGain;

(* =========================================================================
   SKID resolution - ratio preserving
   -------------------------------------------------------------------------
   Naive mix, then if either side exceeds full stroke, scale BOTH by the same
   factor. Clipping only the saturated side would silently destroy the
   commanded ratio: ask for a 2:0 differential, get 1:0, and the machine
   "won't turn at speed" - a complaint you hear about a lot of competitors.
   ========================================================================= *)
rSkidL := rP + rSteerEff;
rSkidR := rP - rSteerEff;

rPeak := ABS(rSkidL);
IF ABS(rSkidR) > rPeak THEN
    rPeak := ABS(rSkidR);
END_IF;

IF rPeak > 1.0 THEN
    rScale := 1.0 / rPeak;
    rSkidL := rSkidL * rScale;
    rSkidR := rSkidR * rScale;
    xSaturated := TRUE;
ELSE
    xSaturated := FALSE;
END_IF;

(* =========================================================================
   CRAWLER resolution - forward speed preserving
   -------------------------------------------------------------------------
   Give the steering only the headroom left above the propel command, so the
   sum (rLeft + rRight) stays at 2*rPropel and the machine keeps pushing.
   Where there is not enough headroom to honour the minimum steering
   authority, back the propel command off just far enough to make room -
   which is still far less speed than skid mode would have given away.
   ========================================================================= *)
rPcraw    := rP;
rHeadroom := 1.0 - ABS(rPcraw);
rSteerReq := ABS(rSteerEff) * rMinSteerAuth;

IF rHeadroom < rSteerReq THEN
    (* not enough room - concede the minimum amount of speed *)
    IF rPcraw >= 0.0 THEN
        rPcraw := 1.0 - rSteerReq;
    ELSE
        rPcraw := -(1.0 - rSteerReq);
    END_IF;
    rHeadroom  := rSteerReq;
    xSaturated := TRUE;
END_IF;

rSteerLim := ABS(rSteerEff);
IF rSteerLim > rHeadroom THEN
    rSteerLim  := rHeadroom;
    xSaturated := TRUE;
END_IF;

IF rSteerEff < 0.0 THEN
    rSteerLim := -rSteerLim;
END_IF;

rCrawL := rPcraw + rSteerLim;
rCrawR := rPcraw - rSteerLim;

(* =========================================================================
   Blend the two resolutions
   -------------------------------------------------------------------------
   Blending the OUTPUTS rather than switching between strategies means the
   operator can be handed a continuous knob, and a work-mode change does not
   produce a step in track command mid-manoeuvre.
   ========================================================================= *)
rLeft  := rPrio * rSkidL + (1.0 - rPrio) * rCrawL;
rRight := rPrio * rSkidR + (1.0 - rPrio) * rCrawR;

(* --- apply mode limit and protection derate ------------------------------ *)
(* Both are pure multipliers applied AFTER the mix, so creep mode and
   anti-stall slow the machine down without changing the steering geometry.
   That is the property that makes creep mode usable for finish work. *)
rLimit := rSpeedScale * rDerate;
IF rLimit < 0.0 THEN rLimit := 0.0; END_IF;
IF rLimit > 1.0 THEN rLimit := 1.0; END_IF;

rLeft  := rLeft  * rLimit;
rRight := rRight * rLimit;
