(*
    FB_AuxControl.st

    Proportional auxiliary hydraulic control with detent latch, attachment
    profile limits, high-flow interlocks and over-pressure protection.

    This block is where attachment-heavy customers decide whether they like
    your machine. The three things that matter, in order:

      1. Proportional, ramped flow - so a grapple can be feathered.
      2. A detent that still MODULATES - most machines force an unlatch to
         change flow, which means an operator running a cold planer has to
         re-latch every time they adjust. Here the rocker keeps authority
         while latched, and the latch just means "do not return to zero when
         I let go".
      3. Interlocks that protect the attachment without being mysterious -
         every refusal sets an output the display turns into a sentence.
*)
FUNCTION_BLOCK FB_AuxControl
VAR_INPUT
    rRocker         : REAL;    (* -1..+1 raw from the proportional thumb rocker *)
    stAttach        : ST_AttachmentProfile;
    stProfile       : ST_OperatorProfile;

    xDetentEvent    : BOOL;    (* pulse from FUNC_AUX_DETENT                  *)
    xHighFlowEvent  : BOOL;    (* pulse from FUNC_HIGH_FLOW_TOGGLE            *)

    rAuxPressureBar : REAL;
    rOilTempC       : REAL;
    rEngineRpm      : REAL;
    rWorkDerate     : REAL := 1.0;   (* from FB_AntiStall stage 2             *)

    xEnable         : BOOL;    (* operator present, engine running            *)
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rAuxCmd         : REAL;    (* -1..+1 to the PVG section over CAN          *)
    xDetentActive   : BOOL;
    xHighFlowActive : BOOL;
    xPressureLimit  : BOOL;    (* sustained relief - display message          *)
    xHighFlowDenied : BOOL;    (* requested but interlocked out               *)
END_VAR

VAR
    fbRocker        : FB_AxisConditioning;
    stRockerRaw     : ST_RawAxis;
    rShaped         : REAL;
    rTarget         : REAL;
    rLatched        : REAL;
    rStep           : REAL;
    rPressTimer     : REAL;
    rPressDerate    : REAL := 1.0;
    xHighFlowReq    : BOOL;
    xAllowHighFlow  : BOOL;
END_VAR

(* --- condition the rocker exactly like a main axis ------------------------ *)
(* The rocker on a CAN grip is single-element, so the plausibility check has
   nothing to cross-reference; channel B is synthesised. A stuck rocker is far
   less dangerous than a stuck propel axis - it cannot move the machine - and
   the detent release conditions below cover the failure that matters. *)
stRockerRaw.rChA     := rRocker;
stRockerRaw.rChB     := -rRocker;
stRockerRaw.xInRange := TRUE;

fbRocker(
    stRaw     := stRockerRaw,
    rDeadband := C_AXIS_DEADBAND,
    rExpo     := stProfile.rAuxExpo,
    rRateUp   := stAttach.rAuxRampUp,
    rRateDown := stAttach.rAuxRampDown,
    rDt       := rDt,
    xEnable   := xEnable );

rShaped := fbRocker.rCmd;

IF NOT stAttach.xAllowReverse AND rShaped < 0.0 THEN
    rShaped := 0.0;
END_IF;

(* --- detent latch -------------------------------------------------------- *)
IF NOT xEnable OR NOT stAttach.xAllowDetent THEN
    xDetentActive := FALSE;
    rLatched      := 0.0;

ELSIF xDetentEvent THEN
    IF xDetentActive THEN
        xDetentActive := FALSE;
        rLatched      := 0.0;
    ELSIF ABS(rShaped) > 0.10 THEN
        (* Latching from neutral would arm a circuit the operator is not
           currently commanding - refuse it. They must be running the
           attachment at the flow they want before they can lock it. *)
        xDetentActive := TRUE;
        rLatched      := rShaped;
    END_IF;

ELSIF xDetentActive THEN
    IF (rLatched > 0.0 AND rShaped < -0.15) OR
       (rLatched < 0.0 AND rShaped >  0.15) THEN
        (* pushed through neutral the other way - the universal "stop" gesture *)
        xDetentActive := FALSE;
        rLatched      := 0.0;
    ELSIF ABS(rShaped) > 0.10 THEN
        (* still modulating: the latch follows the rocker *)
        rLatched := rShaped;
    END_IF;
END_IF;

IF xDetentActive THEN
    rTarget := rLatched;
ELSE
    rTarget := rShaped;
END_IF;

(* --- over-pressure protection -------------------------------------------- *)
(* Brief relief events are normal - a grapple closing onto a log hits relief
   every cycle. Only SUSTAINED relief means something is jammed, so this is
   timed rather than instantaneous. *)
IF rAuxPressureBar > stAttach.rMaxPressureBar THEN
    rPressTimer := rPressTimer + rDt;
ELSE
    rPressTimer := rPressTimer - rDt * 0.5;
    IF rPressTimer < 0.0 THEN rPressTimer := 0.0; END_IF;
END_IF;

IF rPressTimer > 2.0 THEN
    xPressureLimit := TRUE;
    rPressDerate   := rPressDerate - rDt * 0.5;
    IF rPressDerate < 0.35 THEN rPressDerate := 0.35; END_IF;
ELSE
    xPressureLimit := FALSE;
    rPressDerate   := rPressDerate + rDt * 0.25;
    IF rPressDerate > 1.0 THEN rPressDerate := 1.0; END_IF;
END_IF;

(* --- high flow ----------------------------------------------------------- *)
IF xHighFlowEvent THEN
    xHighFlowReq := NOT xHighFlowReq;
END_IF;

(* Cold oil through a high-flow attachment motor is a known killer of
   attachment warranties. Refuse until the oil is warm, and say why. *)
xAllowHighFlow := stAttach.xAllowHighFlow
              AND rOilTempC > 10.0
              AND rOilTempC < C_OIL_TEMP_DERATE_C
              AND rEngineRpm > 1800.0
              AND xEnable;

xHighFlowActive := xHighFlowReq AND xAllowHighFlow;
xHighFlowDenied := xHighFlowReq AND NOT xAllowHighFlow;

(* --- final scaling ------------------------------------------------------- *)
rAuxCmd := rTarget * stAttach.rMaxFlowScale * rPressDerate * rWorkDerate;

IF NOT xEnable THEN
    (* Ramp to zero rather than dropping it - a latched attachment stopping
       instantly shock-loads its driveline. *)
    rStep := rDt / stAttach.rSoftStartS;
    IF rAuxCmd > rStep THEN
        rAuxCmd := rAuxCmd - rStep;
    ELSIF rAuxCmd < -rStep THEN
        rAuxCmd := rAuxCmd + rStep;
    ELSE
        rAuxCmd := 0.0;
    END_IF;
END_IF;

IF rAuxCmd >  1.0 THEN rAuxCmd :=  1.0; END_IF;
IF rAuxCmd < -1.0 THEN rAuxCmd := -1.0; END_IF;
