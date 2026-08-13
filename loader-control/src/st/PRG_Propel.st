(*
    PRG_Propel.st

    The 10 ms propel task. Wires the conditioning, mixing, protection and
    output blocks into one chain and holds the interlock state machine.

    Data flow:

        HAL raw axes
             |
        FB_AxisConditioning  x2   (deadband, expo, ramps, plausibility)
             |
        FB_DriveMixer             (ratio-preserving mix, steer scheduling)
             |            ^
             |            +------ FB_AntiStall (engine droop derate)
             |            +------ thermal / charge-pressure derate
             |
        FB_ProportionalOut   x2   (threshold compensation, coil selection)
             |
        HAL current outputs

    NOTE ON SAFETY: xPropelEnable below is the FUNCTIONAL interlock. It exists
    so the machine behaves predictably and can tell the operator why it is
    inhibited. It is NOT the safety function. Removing motive power when the
    operator leaves the seat must be done by a rated path - a certified safety
    controller or a dual-channel hardwired chain that cuts coil supply
    independently of this program. See docs/00-architecture.md section 2.
*)
PROGRAM PRG_Propel
VAR
    (* --- function block instances ---------------------------------------- *)
    fbPropelAxis  : FB_AxisConditioning;
    fbSteerAxis   : FB_AxisConditioning;
    fbMixer       : FB_DriveMixer;
    fbAntiStall   : FB_AntiStall;
    fbTraction    : FB_TractiveControl;
    fbLeftPump    : FB_ProportionalOut;
    fbRightPump   : FB_ProportionalOut;

    (* --- state ------------------------------------------------------------ *)
    stProfile        : ST_OperatorProfile;   (* loaded from NVM on startup    *)
    eSpeedMode       : E_SpeedMode := SPEED_LOW;
    eInhibit         : E_InhibitCause := INH_NO_OPERATOR;
    xPropelEnable    : BOOL;
    xNeutralLatched  : BOOL := FALSE;        (* neutral-before-enable latch   *)
    rSpeedScale      : REAL;
    rThermalDerate   : REAL := 1.0;
    rTotalDerate     : REAL;
    rSteerPrio       : REAL;
    rLoadBias        : REAL;
END_VAR

(* =========================================================================
   1. Condition both propel axes
   ========================================================================= *)
fbPropelAxis(
    stRaw       := HAL.stLeftJoyY,
    rDeadband   := C_AXIS_DEADBAND,
    rExpo       := stProfile.rPropelExpo,
    rRateUp     := stProfile.rAccelRate,
    rRateDown   := stProfile.rDecelRate,
    rDt         := C_DT_FAST,
    xEnable     := xPropelEnable,
    xResetFault := HAL.xFaultResetBtn );

fbSteerAxis(
    stRaw       := HAL.stLeftJoyX,
    rDeadband   := C_AXIS_DEADBAND,
    rExpo       := stProfile.rSteerExpo,
    rRateUp     := stProfile.rAccelRate * 1.5,  (* steer may build faster     *)
    rRateDown   := stProfile.rDecelRate,
    rDt         := C_DT_FAST,
    xEnable     := xPropelEnable,
    xResetFault := HAL.xFaultResetBtn );

(* =========================================================================
   2. Interlock state machine (functional layer)
   -------------------------------------------------------------------------
   The neutral-before-enable latch is the important part: an operator sitting
   down with a stick already pushed must not get a moving machine. Once
   dropped, the latch is only re-armed by returning both axes to center.
   ========================================================================= *)
IF NOT (HAL.xSeatSwitch AND HAL.xSeatBarDown) THEN
    eInhibit        := INH_NO_OPERATOR;
    xNeutralLatched := FALSE;
ELSIF NOT HAL.xEngineRunning THEN
    eInhibit        := INH_ENGINE_STOPPED;
    xNeutralLatched := FALSE;
ELSIF fbPropelAxis.xFault OR fbSteerAxis.xFault THEN
    eInhibit        := INH_JOYSTICK_FAULT;
    xNeutralLatched := FALSE;
ELSIF HAL.rChargePressureBar < C_CHARGE_MIN_BAR THEN
    eInhibit        := INH_LOW_CHARGE;
ELSIF HAL.rOilTempC > C_OIL_TEMP_STOP_C THEN
    eInhibit        := INH_OVERTEMP;
ELSIF NOT xNeutralLatched THEN
    (* Waiting for the operator to center the sticks. *)
    IF fbPropelAxis.xAtNeutral AND fbSteerAxis.xAtNeutral THEN
        xNeutralLatched := TRUE;
        eInhibit        := INH_NONE;
    ELSE
        eInhibit := INH_NOT_NEUTRAL;
    END_IF;
ELSE
    eInhibit := INH_NONE;
END_IF;

xPropelEnable := (eInhibit = INH_NONE);

(* =========================================================================
   3. Protection derates
   ========================================================================= *)
fbAntiStall(
    rEngineRpm       := HAL.rEngineRpm,
    rEngineTargetRpm := HAL.rEngineTargetRpm,
    rDt              := C_DT_FAST,
    xEnable          := TRUE,
    xEngineRunning   := HAL.xEngineRunning,
    xCanValid        := HAL.xJ1939Valid );

(* Linear thermal rollback between the derate and stop thresholds. *)
IF HAL.rOilTempC <= C_OIL_TEMP_DERATE_C THEN
    rThermalDerate := 1.0;
ELSE
    rThermalDerate := 1.0 - 0.7 *
        (HAL.rOilTempC - C_OIL_TEMP_DERATE_C) /
        (C_OIL_TEMP_STOP_C - C_OIL_TEMP_DERATE_C);
    IF rThermalDerate < 0.3 THEN rThermalDerate := 0.3; END_IF;
END_IF;

rTotalDerate := fbAntiStall.rPropelDerate * rThermalDerate;

(* =========================================================================
   4. Speed mode -> top-speed clamp
   -------------------------------------------------------------------------
   Creep is a hard clamp on ground speed that is deliberately independent of
   engine speed, so a cold planer or mulcher can run at rated rpm while the
   machine crawls. This is the mode operators of attachment-heavy fleets ask
   for by name and many competitors either omit or tie to throttle.
   ========================================================================= *)
CASE eSpeedMode OF
    SPEED_CREEP:
        rSpeedScale := HAL.rCreepSetting;     (* 0.05 .. 0.35, from display   *)
        HAL.xTwoSpeedSolenoid := FALSE;
    SPEED_LOW:
        rSpeedScale := stProfile.rMaxSpeedScale;
        HAL.xTwoSpeedSolenoid := FALSE;
    SPEED_HIGH:
        rSpeedScale := stProfile.rMaxSpeedScale;
        (* Do not shift under a hard turn or the machine lurches. *)
        HAL.xTwoSpeedSolenoid := ABS(fbSteerAxis.rCmd) < 0.35;
END_CASE;

(* =========================================================================
   5. Mix and drive the pumps
   ========================================================================= *)
(* --- steering strategy: skid vs crawler ---------------------------------
   The machine BECOMES A CRAWLER LOADER AS THE LOAD COMES ON. Light work gets
   the operator's chosen bias - usually near-skid, for a tight turning radius
   in confined spaces. As tractive effort builds, the mix slides toward
   crawler behaviour so the machine keeps pushing through a steering
   correction instead of washing out of the cut.

   That transition is the crossover concept in one variable, and the operator
   never has to ask for it.

   rEffortPct is one scan old here (FB_TractiveControl runs after the mixer).
   At 10 ms that is immaterial - tractive load does not change in 10 ms. *)
rSteerPrio := stProfile.rSteerPriority;

IF fbTraction.rEffortPct > 60.0 THEN
    rLoadBias := (fbTraction.rEffortPct - 60.0) / 40.0;
    IF rLoadBias > 1.0 THEN rLoadBias := 1.0; END_IF;
    rSteerPrio := rSteerPrio * (1.0 - rLoadBias);
END_IF;

(* Precision work overrides everything: in creep the operator wants the tight,
   predictable radius, not tractive effort. *)
IF eSpeedMode = SPEED_CREEP THEN
    rSteerPrio := 1.0;
END_IF;

fbMixer(
    rPropel         := fbPropelAxis.rCmd,
    rSteer          := fbSteerAxis.rCmd,
    rSpeedScale     := rSpeedScale,
    rDerate         := rTotalDerate,
    rSteerGainAtTop := stProfile.rSteerGainAtTop,
    rSteerPriority  := rSteerPrio );

(* --- rimpull ceiling and slip control ------------------------------------ *)
fbTraction(
    rCmdLeft        := fbMixer.rLeft,
    rCmdRight       := fbMixer.rRight,
    rPressLeftBar   := HAL.rPropelPressLeftBar,
    rPressRightBar  := HAL.rPropelPressRightBar,
    rTrackSpeedL    := HAL.rTrackSpeedLeftKph,
    rTrackSpeedR    := HAL.rTrackSpeedRightKph,
    rLongAccel      := HAL.rImuLongAccel,
    rRimpullSetting := stProfile.rRimpullSetting,
    xSlipControlOn  := HAL.xSlipControlEnabled,
    xEnable         := xPropelEnable,
    rDt             := C_DT_FAST );

fbLeftPump(
    rCmd        := fbTraction.rOutLeft,
    rIThreshold := C_PUMP_I_THRESHOLD,
    rIMax       := C_PUMP_I_MAX,
    xEnable     := xPropelEnable );

fbRightPump(
    rCmd        := fbTraction.rOutRight,
    rIThreshold := C_PUMP_I_THRESHOLD,
    rIMax       := C_PUMP_I_MAX,
    xEnable     := xPropelEnable );

HAL.rLeftPumpFwdCurrent  := fbLeftPump.rIPos;
HAL.rLeftPumpRevCurrent  := fbLeftPump.rINeg;
HAL.rRightPumpFwdCurrent := fbRightPump.rIPos;
HAL.rRightPumpRevCurrent := fbRightPump.rINeg;

(* Park brake follows the functional enable; the rated cut is in parallel. *)
HAL.xParkBrakeRelease := xPropelEnable AND NOT HAL.xParkBrakeRequest;

(* Published for the display and the data logger. *)
HAL.eActiveInhibit    := eInhibit;
HAL.xAntiStallActive  := fbAntiStall.xActive;
HAL.rAntiStallDroop   := fbAntiStall.rDroopRpm;
HAL.rWorkDerate       := fbAntiStall.rWorkDerate;

(* Crossover feature status - the display makes these visible, because a
   feature the operator cannot see working is a feature they do not believe
   in. "Rimpull limiting" showing on screen while the bucket fills is the
   whole sales demonstration. *)
HAL.rTractiveEffortPct := fbTraction.rEffortPct;
HAL.xIndRimpullActive  := fbTraction.xRimpullActive;
HAL.xIndSlip           := fbTraction.xSlipLeft OR fbTraction.xSlipRight;
HAL.rGroundSpeedKph    := fbTraction.rGroundSpeedKph;
HAL.rSteerPriority     := rSteerPrio;
