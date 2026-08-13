(*
    FB_LoaderControl.st

    Boom and bucket control: operator commands plus self-level, return-to-dig,
    return-to-carry, height limit, float and bucket shake.

    ARBITRATION RULE, applied everywhere in this block: the operator always
    wins. Any assisted function yields the instant the operator touches the
    axis that function is driving, and does not resume by itself. Automation
    that fights the stick is worse than no automation - it is the single
    fastest way to make an experienced operator hate a machine.
*)
FUNCTION_BLOCK FB_LoaderControl
VAR_INPUT
    rLiftCmd        : REAL;   (* -1..+1 conditioned, + = raise               *)
    rTiltCmd        : REAL;   (* -1..+1 conditioned, + = curl back           *)

    rBoomAngleDeg   : REAL;   (* from the boom rotary sensor                 *)
    rTiltAngleDeg   : REAL;   (* from the bucket rotary sensor               *)

    xSelfLevelTog   : BOOL;   (* pulse: FUNC_SELF_LEVEL_TOGGLE               *)
    xReturnToDig    : BOOL;   (* pulse: FUNC_RETURN_TO_DIG                   *)
    xTeachDig       : BOOL;   (* pulse: FUNC_TEACH_DIG                       *)
    xReturnToCarry  : BOOL;   (* pulse: FUNC_RETURN_TO_CARRY                 *)
    xTeachCarry     : BOOL;   (* pulse: FUNC_TEACH_CARRY                     *)
    xFloatTog       : BOOL;   (* pulse: FUNC_FLOAT_TOGGLE                    *)
    xHeightLimTog   : BOOL;   (* pulse: FUNC_HEIGHT_LIM_TOGGLE               *)
    xTeachHeightLim : BOOL;   (* pulse: FUNC_TEACH_HEIGHT_LIM                *)
    xShake          : BOOL;   (* pulse: FUNC_BUCKET_SHAKE                    *)

    rWorkDerate     : REAL := 1.0;
    xEnable         : BOOL;
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rLiftOut        : REAL;
    rTiltOut        : REAL;
    xFloatOut       : BOOL;
    xSelfLevelOn    : BOOL;
    xAssistActive   : BOOL;   (* RTD/RTC running - display indicator          *)
    xAtHeightLimit  : BOOL;
END_VAR

VAR CONSTANT
    (* --- linkage geometry: CALIBRATION VALUES ---------------------------
       C_COUPLING is the degrees of apparent bucket rotation per degree of
       boom rotation for this linkage. Measure it: park the machine, disable
       self-level, sweep the boom through its range with the tilt cylinder
       locked, and record both sensors. On a radial-lift loader it is close to
       -1.0; on a vertical-lift linkage it is not, and it is not constant
       either - if the error at the extremes bothers you, replace this
       constant with a lookup table indexed on boom angle. *)
    C_COUPLING       : REAL := -0.92;
    C_LEVEL_FF       : REAL := 0.055;   (* tilt cmd per deg/s of boom rate    *)
    C_LEVEL_KP       : REAL := 0.030;   (* tilt cmd per deg of angle error    *)
    C_LEVEL_MAX      : REAL := 0.75;    (* self-level authority clamp         *)

    C_ASSIST_KP      : REAL := 0.045;   (* RTD/RTC approach gain              *)
    C_ASSIST_MAX     : REAL := 0.65;
    C_ASSIST_TOL_DEG : REAL := 1.5;
    C_ASSIST_TIMEOUT : REAL := 6.0;     (* s - abandon if it cannot get there *)

    C_OPERATOR_BREAK : REAL := 0.08;    (* stick movement that cancels assist *)
    C_FLOAT_MAX_DEG  : REAL := 8.0;     (* boom must be low to enter float    *)
    C_HEIGHT_FADE_DEG: REAL := 6.0;     (* soft approach band to the limit    *)

    C_SHAKE_HZ       : REAL := 4.0;
    C_SHAKE_AMP      : REAL := 0.45;
    C_SHAKE_TIME     : REAL := 0.9;     (* s                                  *)
END_VAR

VAR
    rGroundAngle   : REAL;
    rBoomPrev      : REAL;
    rBoomVel       : REAL;
    rBoomVelFilt   : REAL;

    rLevelTarget   : REAL;
    rDigAngle      : REAL := 0.0;
    rCarryAngle    : REAL := 0.0;
    rHeightLimit   : REAL := 90.0;
    xHeightLimOn   : BOOL;

    xRtdActive     : BOOL;
    xRtcActive     : BOOL;
    rAssistTarget  : REAL;
    rAssistTimer   : REAL;
    rAssistErr     : REAL;

    rShakeTimer    : REAL;
    rShakePhase    : REAL;

    rLevelCmd      : REAL;
    rFade          : REAL;
    xInit          : BOOL;
END_VAR

(* --- bucket angle relative to ground ------------------------------------- *)
rGroundAngle := rTiltAngleDeg + C_COUPLING * rBoomAngleDeg;

(* --- filtered boom rate, for the self-level feed-forward ------------------ *)
IF NOT xInit THEN
    rBoomPrev    := rBoomAngleDeg;
    rLevelTarget := rGroundAngle;
    xInit        := TRUE;
END_IF;

rBoomVel     := (rBoomAngleDeg - rBoomPrev) / rDt;
rBoomPrev    := rBoomAngleDeg;
rBoomVelFilt := rBoomVelFilt + 0.25 * (rBoomVel - rBoomVelFilt);

(* --- teach and toggle ---------------------------------------------------- *)
IF xTeachDig       THEN rDigAngle    := rGroundAngle;  END_IF;
IF xTeachCarry     THEN rCarryAngle  := rGroundAngle;  END_IF;
IF xTeachHeightLim THEN rHeightLimit := rBoomAngleDeg; END_IF;
IF xHeightLimTog   THEN xHeightLimOn := NOT xHeightLimOn; END_IF;
IF xSelfLevelTog   THEN xSelfLevelOn := NOT xSelfLevelOn; END_IF;

IF NOT xEnable THEN
    xRtdActive := FALSE;
    xRtcActive := FALSE;
    xFloatOut  := FALSE;
    rShakeTimer := 0.0;
END_IF;

(* --- float --------------------------------------------------------------- *)
(* Only enterable with the boom already low. Letting an operator select float
   with the boom in the air drops the loader under gravity, which is a genuine
   crush hazard and a warranty claim waiting to happen. *)
IF xFloatTog AND xEnable THEN
    IF xFloatOut THEN
        xFloatOut := FALSE;
    ELSIF rBoomAngleDeg < C_FLOAT_MAX_DEG THEN
        xFloatOut := TRUE;
    END_IF;
END_IF;

IF ABS(rLiftCmd) > C_OPERATOR_BREAK THEN
    xFloatOut := FALSE;      (* any lift input drops out of float *)
END_IF;

(* --- return to dig / carry ----------------------------------------------- *)
IF xReturnToDig AND xEnable THEN
    xRtdActive    := TRUE;
    xRtcActive    := FALSE;
    rAssistTarget := rDigAngle;
    rAssistTimer  := 0.0;
END_IF;

IF xReturnToCarry AND xEnable THEN
    xRtcActive    := TRUE;
    xRtdActive    := FALSE;
    rAssistTarget := rCarryAngle;
    rAssistTimer  := 0.0;
END_IF;

xAssistActive := xRtdActive OR xRtcActive;

IF xAssistActive THEN
    rAssistTimer := rAssistTimer + rDt;
    rAssistErr   := rAssistTarget - rGroundAngle;

    (* operator wins - see the arbitration rule at the top *)
    IF ABS(rTiltCmd) > C_OPERATOR_BREAK
       OR ABS(rAssistErr) < C_ASSIST_TOL_DEG
       OR rAssistTimer > C_ASSIST_TIMEOUT THEN
        xRtdActive    := FALSE;
        xRtcActive    := FALSE;
        xAssistActive := FALSE;
    END_IF;
END_IF;

(* --- bucket shake -------------------------------------------------------- *)
IF xShake AND xEnable AND ABS(rTiltCmd) <= C_OPERATOR_BREAK THEN
    rShakeTimer := C_SHAKE_TIME;
    rShakePhase := 0.0;
END_IF;

IF rShakeTimer > 0.0 THEN
    rShakeTimer := rShakeTimer - rDt;
    rShakePhase := rShakePhase + 2.0 * 3.14159265 * C_SHAKE_HZ * rDt;
    IF ABS(rTiltCmd) > C_OPERATOR_BREAK THEN
        rShakeTimer := 0.0;
    END_IF;
END_IF;

(* =========================================================================
   TILT output arbitration, highest priority first
   ========================================================================= *)
IF NOT xEnable THEN
    rTiltOut := 0.0;

ELSIF ABS(rTiltCmd) > C_OPERATOR_BREAK THEN
    (* operator commanding: pass through, and re-capture the self-level target
       so releasing the stick holds the angle they just chose *)
    rTiltOut     := rTiltCmd;
    rLevelTarget := rGroundAngle;

ELSIF rShakeTimer > 0.0 THEN
    rTiltOut := C_SHAKE_AMP * SIN(rShakePhase);

ELSIF xAssistActive THEN
    rTiltOut := C_ASSIST_KP * rAssistErr;
    IF rTiltOut >  C_ASSIST_MAX THEN rTiltOut :=  C_ASSIST_MAX; END_IF;
    IF rTiltOut < -C_ASSIST_MAX THEN rTiltOut := -C_ASSIST_MAX; END_IF;
    rLevelTarget := rGroundAngle;

ELSIF xSelfLevelOn THEN
    (* Feed-forward does the work, the P term only cleans up residual error.
       Levelling on BOTH raise and lower - most competitors do raise only, and
       the difference shows up within one load cycle. *)
    rLevelCmd := -C_LEVEL_FF * rBoomVelFilt * C_COUPLING
               +  C_LEVEL_KP * (rLevelTarget - rGroundAngle);
    IF rLevelCmd >  C_LEVEL_MAX THEN rLevelCmd :=  C_LEVEL_MAX; END_IF;
    IF rLevelCmd < -C_LEVEL_MAX THEN rLevelCmd := -C_LEVEL_MAX; END_IF;
    rTiltOut := rLevelCmd;

ELSE
    rTiltOut     := 0.0;
    rLevelTarget := rGroundAngle;
END_IF;

(* =========================================================================
   LIFT output, with the height limit faded in rather than stepped
   ========================================================================= *)
IF NOT xEnable OR xFloatOut THEN
    rLiftOut := 0.0;
ELSE
    rLiftOut := rLiftCmd;

    IF xHeightLimOn AND rLiftCmd > 0.0 THEN
        rFade := (rHeightLimit - rBoomAngleDeg) / C_HEIGHT_FADE_DEG;
        IF rFade < 0.0 THEN rFade := 0.0; END_IF;
        IF rFade > 1.0 THEN rFade := 1.0; END_IF;
        rLiftOut       := rLiftOut * rFade;
        xAtHeightLimit := rFade < 0.05;
    ELSE
        xAtHeightLimit := FALSE;
    END_IF;
END_IF;

(* --- anti-stall stage 2 trim applies to both sections -------------------- *)
rLiftOut := rLiftOut * rWorkDerate;
rTiltOut := rTiltOut * rWorkDerate;
