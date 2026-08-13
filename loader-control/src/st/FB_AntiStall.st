(*
    FB_AntiStall.st

    Engine droop -> propel derate, with the priority ordering that makes a
    machine feel strong.

    THE IDEA. When you drive a loaded bucket into a pile, the hydrostat and the
    work pump both pull on the same engine. If nothing intervenes, engine speed
    collapses, the work hydraulics slow down, and the operator loses the ability
    to curl and lift out of the cut. The instinctive operator response is to
    back off the propel stick - so a machine WITHOUT anti-stall is really a
    machine that makes the operator do this control loop manually, badly, all
    day long.

    THE PRIORITY THAT MATTERS. Most implementations derate everything together.
    That is the wrong answer. Tractive effort is what is overloading the engine;
    lift and curl are what get you out of the cut. So:

        stage 1: cut PROPEL, progressively, down to C_STALL_DERATE_MIN
        stage 2: only if droop is still growing with propel already at minimum,
                 begin trimming WORK hydraulics

    Getting this ordering right is most of why some machines feel like they
    have more engine than the spec sheet says.

    TUNING NOTE. Kp/Ki in GVL_Types are a credible starting point for a ~70 hp
    machine with a closed-loop hydrostat, not a finished calibration. Expect to
    spend a day on a pile with a laptop. Symptoms: too much Ki and the machine
    surges in the cut; too much Kp and it feels like the propel stick has a
    dead spot under load.
*)
FUNCTION_BLOCK FB_AntiStall
VAR_INPUT
    rEngineRpm      : REAL;   (* actual, from J1939 EEC1                      *)
    rEngineTargetRpm: REAL;   (* commanded, what we asked for via TSC1        *)
    rDt             : REAL := 0.010;
    xEnable         : BOOL;   (* FALSE = passthrough, for diagnostics/testing *)
    xEngineRunning  : BOOL;
    xCanValid       : BOOL;   (* engine data fresh; stale data must not derate*)
END_VAR

VAR_OUTPUT
    rPropelDerate   : REAL := 1.0;  (* multiplier into FB_DriveMixer          *)
    rWorkDerate     : REAL := 1.0;  (* multiplier into loader/aux commands    *)
    xActive         : BOOL;         (* for the display: "anti-stall working"  *)
    rDroopRpm       : REAL;         (* diagnostics / data logging             *)
END_VAR

VAR
    rError          : REAL;
    rIntegral       : REAL;
    rReduction      : REAL;
    rRecoverStep    : REAL;
    rStage2         : REAL;
END_VAR

(* --- bail out to passthrough when we cannot trust the inputs -------------- *)
(* A CAN timeout must NOT be allowed to look like a stall. Failing to
   full derate on stale data would strand the machine in the cut. *)
IF NOT xEnable OR NOT xEngineRunning OR NOT xCanValid THEN
    rIntegral     := 0.0;
    rPropelDerate := 1.0;
    rWorkDerate   := 1.0;
    xActive       := FALSE;
    rDroopRpm     := 0.0;
    RETURN;
END_IF;

rDroopRpm := rEngineTargetRpm - rEngineRpm;

(* --- inside the dead zone: bleed the integrator and blend back out ------- *)
IF rDroopRpm <= C_STALL_DROOP_START THEN
    rIntegral := 0.0;
    xActive   := FALSE;

    (* Blend the derate back out over C_STALL_RECOVER_S rather than releasing
       it in one scan. A step release dumps full displacement back into the
       pump and the machine lunges out of the pile. *)
    rRecoverStep := rDt / C_STALL_RECOVER_S;
    rPropelDerate := rPropelDerate + rRecoverStep;
    rWorkDerate   := rWorkDerate   + rRecoverStep;
    IF rPropelDerate > 1.0 THEN rPropelDerate := 1.0; END_IF;
    IF rWorkDerate   > 1.0 THEN rWorkDerate   := 1.0; END_IF;
    RETURN;
END_IF;

(* --- stage 1: PI on the droop beyond the dead zone, cutting propel ------- *)
xActive := TRUE;
rError  := rDroopRpm - C_STALL_DROOP_START;

rIntegral := rIntegral + rError * rDt;

(* Anti-windup: clamp the integral to the span that can produce full derate.
   Without this, a long dig winds the integrator up and the machine stays
   derated for seconds after the load is gone. *)
IF rIntegral * C_STALL_KI > 1.0 THEN
    rIntegral := 1.0 / C_STALL_KI;
ELSIF rIntegral < 0.0 THEN
    rIntegral := 0.0;
END_IF;

rReduction := C_STALL_KP * rError + C_STALL_KI * rIntegral;
IF rReduction < 0.0 THEN rReduction := 0.0; END_IF;
IF rReduction > 1.0 THEN rReduction := 1.0; END_IF;

rPropelDerate := 1.0 - rReduction * (1.0 - C_STALL_DERATE_MIN);
IF rPropelDerate < C_STALL_DERATE_MIN THEN
    rPropelDerate := C_STALL_DERATE_MIN;
END_IF;

(* --- stage 2: propel is at its floor and the engine is still going down --- *)
(* Only now do we touch the work hydraulics, and gently - trimming to 60% at
   the point where the engine would otherwise stall outright. *)
IF rDroopRpm > C_STALL_DROOP_FULL THEN
    rStage2 := (rDroopRpm - C_STALL_DROOP_FULL) / C_STALL_DROOP_FULL;
    IF rStage2 > 1.0 THEN rStage2 := 1.0; END_IF;
    rWorkDerate := 1.0 - 0.40 * rStage2;
ELSE
    rWorkDerate := 1.0;
END_IF;
