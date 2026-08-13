(*
    FB_ProportionalOut.st

    Normalized bidirectional command (-1..+1)  ->  two coil currents.

    A proportional pump control or valve spool does nothing at all until the
    solenoid current reaches its threshold. If you map 0..1 linearly onto
    0..I_MAX, the first ~35% of joystick travel produces heat and no motion.
    That is the mushy, disconnected feel that separates a cheap machine from
    a good one, and it costs nothing to fix: map the ACTIVE command range onto
    I_THRESHOLD..I_MAX so the very first millimetre of stick movement produces
    visible machine movement.

    Also handles:
      - direction selection between the two coils of an opposed pair
      - a small hysteresis band at zero so electrical noise cannot chatter the
        pump across neutral
      - dither passthrough (the HAL superimposes it on the PWM)
*)
FUNCTION_BLOCK FB_ProportionalOut
VAR_INPUT
    rCmd         : REAL;                  (* -1.0 .. +1.0                     *)
    rIThreshold  : REAL := 0.400;         (* A, start of spool/swash movement *)
    rIMax        : REAL := 1.100;         (* A, full stroke                   *)
    rZeroBand    : REAL := 0.015;         (* command units, anti-chatter      *)
    xEnable      : BOOL;                  (* FALSE forces both coils to zero  *)
END_VAR

VAR_OUTPUT
    rIPos        : REAL;   (* A, coil driving the positive direction          *)
    rINeg        : REAL;   (* A, coil driving the negative direction          *)
    rDitherHz    : REAL;   (* passed to the HAL current controller            *)
END_VAR

VAR
    rMag         : REAL;
    rCurrent     : REAL;
END_VAR

rDitherHz := C_DITHER_HZ;

IF NOT xEnable THEN
    rIPos := 0.0;
    rINeg := 0.0;
    RETURN;
END_IF;

rMag := ABS(rCmd);

IF rMag <= rZeroBand THEN
    (* Genuinely neutral: both coils dead. Do not hold threshold current here -
       it warms the oil for no reason and can creep a worn pump. *)
    rIPos := 0.0;
    rINeg := 0.0;
    RETURN;
END_IF;

IF rMag > 1.0 THEN
    rMag := 1.0;
END_IF;

(* Threshold compensation: the useful command range starts AT the threshold. *)
rCurrent := rIThreshold + (rIMax - rIThreshold) * rMag;

IF rCmd > 0.0 THEN
    rIPos := rCurrent;
    rINeg := 0.0;
ELSE
    rIPos := 0.0;
    rINeg := rCurrent;
END_IF;
