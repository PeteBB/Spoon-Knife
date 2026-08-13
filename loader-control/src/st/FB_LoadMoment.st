(*
    FB_LoadMoment.st

    Payload weighing and load moment indication.

    ---------------------------------------------------------------------------
    WHY THIS BLOCK EXISTS

    A machine rated at 5,000 lb has enough capacity to tip itself, and nothing
    in this class ships a load moment indicator. Telehandlers are required to
    have one; a CTL at this capacity arguably should.

    Every sensor it needs is already fitted for something else - lift cylinder
    pressure for payload weighing, boom angle for self-levelling, the IMU for
    slip control. This block is arithmetic on hardware you are already buying,
    and it delivers a safety feature, a spec-sheet line and a liability
    position at once.

    ---------------------------------------------------------------------------
    THE BEHAVIOUR MATTERS MORE THAN THE MATHS

    A machine that simply cuts out at the limit is a machine operators learn to
    disable, and a disabled protection protects nobody. So:

      - warn early and clearly, while there is still time to act
      - degrade progressively rather than switching off
      - NEVER restrict lowering the load

    That last one is absolute. Lowering is the control that always improves the
    situation, and taking it away at the moment of highest stress would turn
    this block from a safety feature into a hazard. It is enforced structurally
    below: the limit output only ever multiplies a RAISE command.

    ---------------------------------------------------------------------------
    CALIBRATION - none of the tables below are real

    The tables are plausible shapes with placeholder numbers. They MUST be
    replaced with measured data:

      tare pressure   - sweep the boom with an empty bucket, log pressure vs angle
      lb per bar      - repeat with several known weights in the bucket
      load arm/height - from the linkage CAD, or measured on the machine

    Payload weighing accuracy is dominated by hydraulic hysteresis and by
    whether the boom is moving. Real implementations weigh only during a steady
    raise through a defined angle window, which is what xWeightValid marks.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_LoadMoment
VAR_INPUT
    rLiftPressureBar : REAL;   (* head end of the lift cylinders              *)
    rBoomAngleDeg    : REAL;
    rBoomRateDegS    : REAL;   (* for the steady-motion weighing window       *)

    rPitchDeg        : REAL;   (* IMU, + = nose up                            *)
    rRollDeg         : REAL;   (* IMU, for the display; not yet in the margin *)

    rRearBallastLb   : REAL;   (* measured on the hitch, or operator-entered  *)

    xEnable          : BOOL;
    rDt              : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rPayloadLb       : REAL;
    xWeightValid     : BOOL;   (* payload figure is trustworthy right now     *)
    rLastGoodLb      : REAL;   (* held value, for the display and totals      *)

    rStabilityPct    : REAL;   (* 100 = level and empty, 0 = at tipping       *)
    eWarnLevel       : INT;    (* 0 none, 1 caution, 2 warning, 3 limiting    *)
    rRaiseLimit      : REAL;   (* 0..1 multiplier - RAISE ONLY, never lower   *)
    xOverload        : BOOL;   (* payload above rated capacity                *)
END_VAR

VAR CONSTANT
    (* --- table axis ------------------------------------------------------- *)
    C_ANGLE_MIN   : REAL := -10.0;
    C_ANGLE_STEP  : REAL := 10.0;
    C_TABLE_N     : INT  := 9;          (* -10 .. +70 degrees *)

    (* --- machine constants: PLACEHOLDERS --------------------------------- *)
    C_MACHINE_LB      : REAL := 16000.0;
    C_MACH_ARM_IN     : REAL := 42.0;   (* fulcrum -> machine CG, horizontal  *)
    C_MACH_CG_HGT_IN  : REAL := 30.0;
    C_BALLAST_ARM_IN  : REAL := 95.0;   (* fulcrum -> hitch                   *)
    C_BALLAST_HGT_IN  : REAL := 20.0;

    C_RATED_LB        : REAL := 5000.0;

    (* --- weighing window -------------------------------------------------- *)
    C_WEIGH_RATE_MIN  : REAL := 2.0;    (* deg/s - must be moving steadily    *)
    C_WEIGH_RATE_MAX  : REAL := 12.0;
    C_WEIGH_ANGLE_LO  : REAL := 5.0;    (* weigh through this arc only        *)
    C_WEIGH_ANGLE_HI  : REAL := 35.0;
    C_WEIGH_SETTLE_S  : REAL := 0.30;

    (* --- staged response -------------------------------------------------- *)
    C_MARGIN_CAUTION  : REAL := 40.0;
    C_MARGIN_WARNING  : REAL := 25.0;
    C_MARGIN_LIMIT_HI : REAL := 20.0;   (* raise starts fading here           *)
    C_MARGIN_LIMIT_LO : REAL := 5.0;    (* raise fully faded here             *)

    C_DEG2RAD         : REAL := 0.0174533;
END_VAR

VAR CONSTANT
    (* Empty-bucket lift pressure vs boom angle, bar. PLACEHOLDER SHAPE:
       rises as the boom comes up and the moment arm grows, then eases as the
       linkage passes over centre. *)
    C_TARE_BAR : ARRAY[0..8] OF REAL :=
        [ 42.0, 48.0, 55.0, 62.0, 68.0, 71.0, 70.0, 66.0, 60.0 ];

    (* Payload pounds per bar above tare, vs boom angle. PLACEHOLDER. *)
    C_LB_PER_BAR : ARRAY[0..8] OF REAL :=
        [ 78.0, 74.0, 70.0, 67.0, 65.0, 64.0, 65.0, 68.0, 73.0 ];

    (* Horizontal distance, front tipping fulcrum to load CG, inches.
       PLACEHOLDER - this is the curve that vertical-lift geometry changes
       most, see docs/06-frame-balance-and-stability.md section 5. *)
    C_LOAD_ARM_IN : ARRAY[0..8] OF REAL :=
        [ 46.0, 44.0, 42.0, 40.0, 39.0, 40.0, 43.0, 48.0, 54.0 ];

    (* Load CG height above ground, inches. PLACEHOLDER. *)
    C_LOAD_HGT_IN : ARRAY[0..8] OF REAL :=
        [ 8.0, 22.0, 38.0, 54.0, 70.0, 86.0, 100.0, 112.0, 120.0 ];
END_VAR

VAR
    rIdxReal     : REAL;
    iIdx         : INT;
    rFrac        : REAL;

    rTare        : REAL;
    rLbPerBar    : REAL;
    rLoadArm     : REAL;
    rLoadHgt     : REAL;

    rPitchRad    : REAL;
    rSinP        : REAL;
    rCosP        : REAL;

    rMomentOver  : REAL;
    rMomentRest  : REAL;
    rSettleTimer : REAL;
    rRaw         : REAL;
END_VAR

IF NOT xEnable THEN
    rPayloadLb    := 0.0;
    xWeightValid  := FALSE;
    rStabilityPct := 100.0;
    eWarnLevel    := 0;
    rRaiseLimit   := 1.0;
    xOverload     := FALSE;
    rSettleTimer  := 0.0;
    RETURN;
END_IF;

(* =========================================================================
   1. Interpolate the geometry tables at the current boom angle
   ========================================================================= *)
rIdxReal := (rBoomAngleDeg - C_ANGLE_MIN) / C_ANGLE_STEP;

IF rIdxReal < 0.0 THEN
    rIdxReal := 0.0;
END_IF;
IF rIdxReal > REAL#8.0 THEN
    rIdxReal := REAL#8.0;
END_IF;

iIdx  := REAL_TO_INT(rIdxReal);
IF iIdx > 7 THEN
    iIdx  := 7;
    rFrac := 1.0;
ELSE
    rFrac := rIdxReal - INT_TO_REAL(iIdx);
END_IF;

rTare     := C_TARE_BAR[iIdx]    + rFrac * (C_TARE_BAR[iIdx+1]    - C_TARE_BAR[iIdx]);
rLbPerBar := C_LB_PER_BAR[iIdx]  + rFrac * (C_LB_PER_BAR[iIdx+1]  - C_LB_PER_BAR[iIdx]);
rLoadArm  := C_LOAD_ARM_IN[iIdx] + rFrac * (C_LOAD_ARM_IN[iIdx+1] - C_LOAD_ARM_IN[iIdx]);
rLoadHgt  := C_LOAD_HGT_IN[iIdx] + rFrac * (C_LOAD_HGT_IN[iIdx+1] - C_LOAD_HGT_IN[iIdx]);

(* =========================================================================
   2. Payload
   -------------------------------------------------------------------------
   Only trustworthy during a steady raise through a defined arc. Outside that
   window the last good figure is held rather than showing the operator a
   number that swings with every hydraulic transient - a payload display that
   dances is one nobody reads.
   ========================================================================= *)
rRaw := (rLiftPressureBar - rTare) * rLbPerBar;
IF rRaw < 0.0 THEN
    rRaw := 0.0;
END_IF;

IF rBoomRateDegS  >  C_WEIGH_RATE_MIN
   AND rBoomRateDegS < C_WEIGH_RATE_MAX
   AND rBoomAngleDeg > C_WEIGH_ANGLE_LO
   AND rBoomAngleDeg < C_WEIGH_ANGLE_HI THEN
    rSettleTimer := rSettleTimer + rDt;
ELSE
    rSettleTimer := 0.0;
END_IF;

xWeightValid := rSettleTimer > C_WEIGH_SETTLE_S;

IF xWeightValid THEN
    (* light filter - the pressure signal is noisy under a moving boom *)
    rLastGoodLb := rLastGoodLb + 0.15 * (rRaw - rLastGoodLb);
END_IF;

rPayloadLb := rRaw;
xOverload  := rLastGoodLb > C_RATED_LB;

(* =========================================================================
   3. Stability margin
   -------------------------------------------------------------------------
   Moments about the front tipping fulcrum, corrected for pitch. A nose-down
   slope shortens every restoring arm and lengthens the overturning one, which
   is exactly the case where the static number on the spec sheet stops being
   true - and exactly when an operator is least likely to be thinking about it.

   This is a rigid-body approximation. It does not model dynamic effects -
   braking, a bucket dropped into the load, ground compliance - so the warning
   thresholds carry the margin for those rather than the maths pretending to.
   ========================================================================= *)
rPitchRad := rPitchDeg * C_DEG2RAD;
rSinP     := SIN(rPitchRad);
rCosP     := COS(rPitchRad);

(* Nose-down (negative pitch) increases the overturning arm by the load height
   term and shrinks the restoring arms. *)
rMomentOver := rRaw * (rLoadArm * rCosP - rLoadHgt * rSinP);
IF rMomentOver < 0.0 THEN
    rMomentOver := 0.0;
END_IF;

rMomentRest := C_MACHINE_LB   * (C_MACH_ARM_IN    * rCosP + C_MACH_CG_HGT_IN * rSinP)
             + rRearBallastLb * (C_BALLAST_ARM_IN * rCosP + C_BALLAST_HGT_IN * rSinP);

IF rMomentRest < 1.0 THEN
    rMomentRest := 1.0;                 (* guard the division *)
END_IF;

rStabilityPct := 100.0 * (1.0 - rMomentOver / rMomentRest);
IF rStabilityPct > 100.0 THEN rStabilityPct := 100.0; END_IF;
IF rStabilityPct < 0.0   THEN rStabilityPct := 0.0;   END_IF;

(* =========================================================================
   4. Staged response
   ========================================================================= *)
IF rStabilityPct > C_MARGIN_CAUTION THEN
    eWarnLevel := 0;
ELSIF rStabilityPct > C_MARGIN_WARNING THEN
    eWarnLevel := 1;
ELSIF rStabilityPct > C_MARGIN_LIMIT_HI THEN
    eWarnLevel := 2;
ELSE
    eWarnLevel := 3;
END_IF;

(* Progressive fade on RAISE. Note what is NOT here: any limit on lowering,
   tilt-back, or propel. Lowering the load is the action that resolves this
   condition, and it stays fully available at every margin. *)
IF rStabilityPct >= C_MARGIN_LIMIT_HI THEN
    rRaiseLimit := 1.0;
ELSIF rStabilityPct <= C_MARGIN_LIMIT_LO THEN
    rRaiseLimit := 0.0;
ELSE
    rRaiseLimit := (rStabilityPct - C_MARGIN_LIMIT_LO)
                 / (C_MARGIN_LIMIT_HI - C_MARGIN_LIMIT_LO);
END_IF;
