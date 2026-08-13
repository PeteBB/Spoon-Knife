(*
    FB_DriveMixer.st

    Propel + steer  ->  left track / right track command.

    This block is the single biggest contributor to how the machine feels, and
    it is where most implementations get lazy. Three decisions:

    (a) SATURATION HANDLING. The naive mix is L = P + S, R = P - S. At full
        forward with full steer that gives L = 2.0, R = 0.0. Clipping L to 1.0
        silently destroys the steering ratio: the operator asked for a 2:0
        differential and got 1:0. The machine "won't turn at speed" - a
        complaint you hear about a lot of competitors' machines.

        Fix: when either side saturates, scale BOTH sides by the same factor.
        Forward speed is sacrificed, the commanded turn geometry is preserved.
        The operator gets the arc they asked for and simply travels it slower,
        which is what they actually wanted.

    (b) SPEED-SCHEDULED STEERING GAIN. Full differential at a standstill (true
        counter-rotation) is essential. That same gain at travel speed makes
        the machine darty and unpleasant, and on a CTL it scrubs the tracks.
        So the steering authority is scheduled down as propel rises.

    (c) COUNTER-ROTATION AUTHORITY. Near zero propel, steer maps straight to
        opposite track commands so the machine spins in its own footprint.
*)
FUNCTION_BLOCK FB_DriveMixer
VAR_INPUT
    rPropel        : REAL;  (* -1..+1, conditioned fore/aft                   *)
    rSteer         : REAL;  (* -1..+1, conditioned left/right, + = right turn *)
    rSpeedScale    : REAL := 1.0;  (* mode/creep top-speed clamp, 0..1        *)
    rDerate        : REAL := 1.0;  (* anti-stall / thermal multiplier, 0..1   *)
    rSteerGainAtTop: REAL := 0.45; (* steering authority at full propel, 0..1 *)
END_VAR

VAR_OUTPUT
    rLeft          : REAL;  (* -1..+1 to left pump                            *)
    rRight         : REAL;  (* -1..+1 to right pump                           *)
    xSaturated     : BOOL;  (* diagnostics: mix was scaled back               *)
END_VAR

VAR
    rSteerGain     : REAL;
    rSteerEff      : REAL;
    rPeak          : REAL;
    rScale         : REAL;
    rLimit         : REAL;
END_VAR

(* --- (b) schedule steering authority against travel speed ---------------- *)
(* At rPropel = 0 the gain is 1.0 (full counter-rotation).
   At |rPropel| = 1 the gain is rSteerGainAtTop. Linear in between: a curve
   here sounds clever but operators read linear as "honest". *)
rSteerGain := 1.0 - (1.0 - rSteerGainAtTop) * ABS(rPropel);
rSteerEff  := rSteer * rSteerGain;

(* --- naive mix ----------------------------------------------------------- *)
rLeft  := rPropel + rSteerEff;
rRight := rPropel - rSteerEff;

(* --- (a) ratio-preserving saturation ------------------------------------- *)
rPeak := ABS(rLeft);
IF ABS(rRight) > rPeak THEN
    rPeak := ABS(rRight);
END_IF;

xSaturated := rPeak > 1.0;
IF xSaturated THEN
    rScale := 1.0 / rPeak;
    rLeft  := rLeft  * rScale;
    rRight := rRight * rScale;
END_IF;

(* --- apply mode limit and protection derate ------------------------------ *)
(* Both are pure multipliers applied AFTER the mix, so creep mode and
   anti-stall slow the machine down without changing the steering geometry.
   That is the property that makes creep mode usable for finish work. *)
rLimit := rSpeedScale * rDerate;
IF rLimit < 0.0 THEN rLimit := 0.0; END_IF;
IF rLimit > 1.0 THEN rLimit := 1.0; END_IF;

rLeft  := rLeft  * rLimit;
rRight := rRight * rLimit;
