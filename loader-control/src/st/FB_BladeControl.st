(*
    FB_BladeControl.st

    Dozer blade: cross-slope hold and blade load control (auto-carry).

    ---------------------------------------------------------------------------
    THIS IS THE THIRD INSTANCE OF ONE PATTERN

        FB_TractiveControl  slip/pressure -> cap rimpull
        FB_HitchControl     draft/slip    -> raise the rear implement
        FB_BladeControl     load/slip     -> raise the front blade   <- here

    All three manage tractive load to prevent slip; they differ only in which
    actuator does the work. The machine therefore has three coordinated levers
    on traction where a competitor has zero or one, and the ordering between
    them is deliberate:

        lift the tool first  - cheap, and the machine keeps working
        cap rimpull second   - blunt, and progress stops

    So the thresholds here and in FB_HitchControl sit BELOW the point at which
    FB_TractiveControl starts cutting effort. Tuning intuition transfers across
    all three; get one right and the others follow.

    ---------------------------------------------------------------------------
    CROSS-SLOPE HOLD is 2D grade control, and it is what lets a novice operator
    cut a flat pad. It needs no GNSS, no base station and no subscription - just
    the IMU already fitted for slip detection and a tilt sensor on the blade.
    Nothing in this class ships it.

    BLADE LOAD CONTROL keeps a full blade moving at a steady load instead of
    the stall-and-back-out cycle that costs an inexperienced operator most of
    their productivity. Rise fast, decay slowly - snapping the blade back down
    the instant load drops just re-buries it and starts the cycle again.
    ---------------------------------------------------------------------------

    Sign conventions:
      rRollDeg        + = machine right side down
      rBladeTiltDeg   + = blade right end down, relative to the machine
      rTargetSlopePct + = finished surface falling to the right
*)
FUNCTION_BLOCK FB_BladeControl
VAR_INPUT
    rLiftCmd         : REAL;   (* -1..+1 operator boom command, + = raise     *)
    rTiltCmd         : REAL;   (* -1..+1 operator blade tilt command          *)

    rRollDeg         : REAL;   (* IMU                                          *)
    rBladeTiltDeg    : REAL;   (* blade tilt sensor, relative to the machine   *)

    rTargetSlopePct  : REAL;   (* operator setpoint, percent grade             *)
    xCrossSlopeOn    : BOOL;

    rPropelPressBar  : REAL;   (* worst-side propel loop pressure              *)
    rTargetLoadPct   : REAL := 70.0;   (* auto-carry setpoint                  *)
    xLoadControlOn   : BOOL;

    xFloatActive     : BOOL;   (* float overrides both assists                 *)
    xEnable          : BOOL;
    rDt              : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rLiftOut         : REAL;
    rTiltOut         : REAL;

    rActualSlopePct  : REAL;   (* live cross-slope, for the display            *)
    xCrossSlopeActive: BOOL;
    xLoadCtrlActive  : BOOL;
END_VAR

VAR CONSTANT
    (* --- CALIBRATION VALUES ---------------------------------------------- *)
    C_SLOPE_KP       : REAL := 0.085;   (* tilt command per degree of error   *)
    C_SLOPE_KI       : REAL := 0.020;
    C_SLOPE_MAX      : REAL := 0.60;    (* assist authority clamp             *)
    C_SLOPE_DEADBAND : REAL := 0.25;    (* deg - stops the blade hunting      *)

    C_LOAD_KP        : REAL := 0.011;   (* lift command per percent overload  *)
    C_LOAD_MAX       : REAL := 0.55;
    C_LOAD_DECAY_S   : REAL := 2.0;     (* how fast the lift washes back out  *)

    C_OPERATOR_BREAK : REAL := 0.08;
    C_PROPEL_MAX_BAR : REAL := 450.0;   (* must match FB_TractiveControl      *)
    C_RAD2DEG        : REAL := 57.29578;
END_VAR

VAR
    rTargetSlopeDeg : REAL;
    rActualSlopeDeg : REAL;
    rSlopeErr       : REAL;
    rSlopeInt       : REAL;
    rSlopeCmd       : REAL;

    rLoadPct        : REAL;
    rLoadErr        : REAL;
    rLoadCorr       : REAL;
    rLoadHeld       : REAL;
END_VAR

(* =========================================================================
   0. Disabled, or float - hand both axes straight back to the operator
   ========================================================================= *)
IF NOT xEnable OR xFloatActive THEN
    rLiftOut          := rLiftCmd;
    rTiltOut          := rTiltCmd;
    rSlopeInt         := 0.0;
    rLoadHeld         := 0.0;
    xCrossSlopeActive := FALSE;
    xLoadCtrlActive   := FALSE;
    RETURN;
END_IF;

(* =========================================================================
   1. Cross-slope
   -------------------------------------------------------------------------
   The blade's slope relative to the WORLD is the machine's roll plus the
   blade's tilt relative to the machine. Holding that constant while the
   machine pitches and rolls over rough ground is the entire trick - and it is
   why this works with a cheap IMU: we are correcting a measured angle, not
   dead-reckoning a position.
   ========================================================================= *)
rActualSlopeDeg := rRollDeg + rBladeTiltDeg;
rActualSlopePct := 100.0 * TAN(rActualSlopeDeg / C_RAD2DEG);

rTargetSlopeDeg := C_RAD2DEG * ATAN(rTargetSlopePct / 100.0);

IF ABS(rTiltCmd) > C_OPERATOR_BREAK THEN
    (* Operator wins, always, and the assist does not resume by itself. *)
    rTiltOut          := rTiltCmd;
    rSlopeInt         := 0.0;
    xCrossSlopeActive := FALSE;

ELSIF xCrossSlopeOn THEN
    rSlopeErr := rTargetSlopeDeg - rActualSlopeDeg;

    IF ABS(rSlopeErr) < C_SLOPE_DEADBAND THEN
        rSlopeCmd := 0.0;
        (* integrator frozen inside the deadband - otherwise it winds up
           against a blade that is already on grade *)
    ELSE
        rSlopeInt := rSlopeInt + rSlopeErr * rDt;
        IF rSlopeInt * C_SLOPE_KI >  C_SLOPE_MAX THEN
            rSlopeInt :=  C_SLOPE_MAX / C_SLOPE_KI;
        ELSIF rSlopeInt * C_SLOPE_KI < -C_SLOPE_MAX THEN
            rSlopeInt := -C_SLOPE_MAX / C_SLOPE_KI;
        END_IF;

        rSlopeCmd := C_SLOPE_KP * rSlopeErr + C_SLOPE_KI * rSlopeInt;
    END_IF;

    IF rSlopeCmd >  C_SLOPE_MAX THEN rSlopeCmd :=  C_SLOPE_MAX; END_IF;
    IF rSlopeCmd < -C_SLOPE_MAX THEN rSlopeCmd := -C_SLOPE_MAX; END_IF;

    rTiltOut          := rSlopeCmd;
    xCrossSlopeActive := TRUE;

ELSE
    rTiltOut          := 0.0;
    rSlopeInt         := 0.0;
    xCrossSlopeActive := FALSE;
END_IF;

(* =========================================================================
   2. Blade load control (auto-carry)
   ========================================================================= *)
rLoadPct := 100.0 * rPropelPressBar / C_PROPEL_MAX_BAR;
IF rLoadPct > 100.0 THEN rLoadPct := 100.0; END_IF;
IF rLoadPct < 0.0   THEN rLoadPct := 0.0;   END_IF;

IF ABS(rLiftCmd) > C_OPERATOR_BREAK THEN
    (* Operator setting a depth - hand the axis over and wash the assist out. *)
    rLiftOut        := rLiftCmd;
    rLoadHeld       := 0.0;
    xLoadCtrlActive := FALSE;

ELSIF xLoadControlOn THEN
    rLoadErr := rLoadPct - rTargetLoadPct;
    IF rLoadErr < 0.0 THEN
        rLoadErr := 0.0;              (* only ever lifts, never digs deeper *)
    END_IF;

    rLoadCorr := C_LOAD_KP * rLoadErr;
    IF rLoadCorr > C_LOAD_MAX THEN rLoadCorr := C_LOAD_MAX; END_IF;

    (* Rise fast, decay slow - see the header. *)
    IF rLoadCorr > rLoadHeld THEN
        rLoadHeld := rLoadCorr;
    ELSE
        rLoadHeld := rLoadHeld - rDt * C_LOAD_MAX / C_LOAD_DECAY_S;
        IF rLoadHeld < 0.0 THEN rLoadHeld := 0.0; END_IF;
    END_IF;

    rLiftOut        := rLoadHeld;
    xLoadCtrlActive := rLoadHeld > 0.01;

ELSE
    rLiftOut        := rLiftCmd;
    rLoadHeld       := 0.0;
    xLoadCtrlActive := FALSE;
END_IF;

IF rLiftOut >  1.0 THEN rLiftOut :=  1.0; END_IF;
IF rLiftOut < -1.0 THEN rLiftOut := -1.0; END_IF;
IF rTiltOut >  1.0 THEN rTiltOut :=  1.0; END_IF;
IF rTiltOut < -1.0 THEN rTiltOut := -1.0; END_IF;
