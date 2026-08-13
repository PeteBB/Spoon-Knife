(*
    PRG_Loader.st

    The 50 ms task: buttons, function dispatch, loader and auxiliary control.

    Chain:

        CAN grip messages
             |
        FB_ButtonInput  x16        (debounce, short/long/double/hold)
             |
        FB_FunctionDispatch        (binding table -> function requests)
             |
        +----+--------------------+
        |                         |
    FB_LoaderControl        FB_AuxControl
        |                         |
        +----+--------------------+
             |
        PVG 32 section commands, transmitted over CAN1

    Propel lives in PRG_Propel on the 10 ms task. Loader and aux are quite
    happy at 50 ms - the hydraulics cannot respond faster than that anyway,
    and the buttons need debounce time regardless.
*)
PROGRAM PRG_Loader
VAR
    (* --- instances -------------------------------------------------------- *)
    afbButtons   : ARRAY[0..C_MAX_BUTTONS-1] OF FB_ButtonInput;
    fbDispatch   : FB_FunctionDispatch;
    fbLiftAxis   : FB_AxisConditioning;
    fbTiltAxis   : FB_AxisConditioning;
    fbLoader     : FB_LoaderControl;
    fbAux        : FB_AuxControl;
    fbLoadMoment : FB_LoadMoment;

    (* --- configuration, restored from NVM at startup ---------------------- *)
    astBindings  : ARRAY[0..C_MAX_BINDINGS-1] OF ST_ButtonBinding;
    stProfile    : ST_OperatorProfile;
    stAttach     : ST_AttachmentProfile;

    (* --- state ------------------------------------------------------------ *)
    xLoaderEnable : BOOL;
    xAux2Latch    : BOOL;
    xLightsLatch  : BOOL;
    xRideCtrlLatch: BOOL;
    i             : INT;
    xConfigLoaded : BOOL;
END_VAR

(* =========================================================================
   0. One-time configuration load
   ========================================================================= *)
IF NOT xConfigLoaded THEN
    (* HAL.RestoreConfig() returns FALSE if the NVM image is missing or its
       CRC fails, in which case we fall back to the shipped defaults rather
       than running with a corrupt binding table. A machine whose buttons do
       something random is worse than one whose buttons are merely not the
       operator's preferred layout. *)
    IF NOT HAL.RestoreBindings(astBindings) THEN
        astBindings := g_astDefaultBindings;
    END_IF;
    IF NOT HAL.RestoreOperatorProfile(stProfile) THEN
        ;  (* struct initialisers already hold sane defaults *)
    END_IF;
    xConfigLoaded := TRUE;
END_IF;

(* Attachment coupling can replace the bindings wholesale - plug in a grapple
   and the trigger becomes clamp without the operator opening a menu. *)
IF HAL.xAttachmentChanged THEN
    stAttach := HAL.stAttachmentProfile;
    IF stAttach.xIsRecognised THEN
        HAL.LoadAttachmentBindings(stAttach.wId, astBindings);
    END_IF;
END_IF;

(* =========================================================================
   1. Decode every button
   ========================================================================= *)
FOR i := 0 TO C_MAX_BUTTONS - 1 DO
    afbButtons[i](
        xRaw          := HAL.axButtonRaw[i],
        xEnableDouble := fbDispatch.axNeedDouble[i],
        rDt           := C_DT_MED );

    fbDispatch.astButtons[i] := afbButtons[i].stState;
END_FOR;

(* =========================================================================
   2. Dispatch gestures to functions
   ========================================================================= *)
(* Suppressed when nobody is in the seat: a button knocked by a tool bag on
   the way out of the cab must not toggle high flow. *)
fbDispatch(
    astBindings := astBindings,
    xEnable     := HAL.xSeatSwitch AND HAL.xSeatBarDown AND HAL.xEngineRunning );

xLoaderEnable := HAL.xSeatSwitch AND HAL.xSeatBarDown AND HAL.xEngineRunning
                 AND HAL.rOilTempC < C_OIL_TEMP_STOP_C;

(* =========================================================================
   3. Simple latching functions handled here
   ========================================================================= *)
IF fbDispatch.axFunction[FUNC_AUX2_TOGGLE]   THEN xAux2Latch     := NOT xAux2Latch;     END_IF;
IF fbDispatch.axFunction[FUNC_WORK_LIGHTS]   THEN xLightsLatch   := NOT xLightsLatch;   END_IF;
IF fbDispatch.axFunction[FUNC_RIDE_CONTROL]  THEN xRideCtrlLatch := NOT xRideCtrlLatch; END_IF;

IF fbDispatch.axFunction[FUNC_PROFILE_NEXT] THEN
    HAL.NextOperatorProfile(stProfile);
END_IF;

(* Engine speed trim - held buttons, so these are levels not pulses. *)
IF fbDispatch.axFunction[FUNC_ENGINE_RPM_UP] THEN
    HAL.rEngineTargetRpm := HAL.rEngineTargetRpm + 300.0 * C_DT_MED;
ELSIF fbDispatch.axFunction[FUNC_ENGINE_RPM_DOWN] THEN
    HAL.rEngineTargetRpm := HAL.rEngineTargetRpm - 300.0 * C_DT_MED;
END_IF;

(* Auto ride control: engage above a speed threshold, drop out below it, but
   only while the operator has it switched on. Loading with ride control live
   makes the bucket bounce, so the low-speed dropout is not optional. *)
HAL.xRideControlSolenoid := xRideCtrlLatch AND HAL.rGroundSpeedKph > 5.0;
HAL.xWorkLights          := xLightsLatch;
HAL.xAux2Solenoid        := xAux2Latch AND xLoaderEnable;

(* =========================================================================
   4. Condition the loader axes
   ========================================================================= *)
fbLiftAxis(
    stRaw       := HAL.stRightJoyY,
    rDeadband   := C_AXIS_DEADBAND,
    rExpo       := stProfile.rLoaderExpo,
    rRateUp     := stProfile.rLoaderRate,
    rRateDown   := stProfile.rLoaderRate * 1.6,
    rDt         := C_DT_MED,
    xEnable     := xLoaderEnable,
    xResetFault := HAL.xFaultResetBtn );

fbTiltAxis(
    stRaw       := HAL.stRightJoyX,
    rDeadband   := C_AXIS_DEADBAND,
    rExpo       := stProfile.rLoaderExpo,
    rRateUp     := stProfile.rLoaderRate,
    rRateDown   := stProfile.rLoaderRate * 1.6,
    rDt         := C_DT_MED,
    xEnable     := xLoaderEnable,
    xResetFault := HAL.xFaultResetBtn );

(* =========================================================================
   5. Loader assists
   ========================================================================= *)
fbLoader(
    rLiftCmd        := fbLiftAxis.rCmd,
    rTiltCmd        := fbTiltAxis.rCmd,
    rBoomAngleDeg   := HAL.rBoomAngleDeg,
    rTiltAngleDeg   := HAL.rTiltAngleDeg,
    xSelfLevelTog   := fbDispatch.axFunction[FUNC_SELF_LEVEL_TOGGLE],
    xReturnToDig    := fbDispatch.axFunction[FUNC_RETURN_TO_DIG],
    xTeachDig       := fbDispatch.axFunction[FUNC_TEACH_DIG],
    xReturnToCarry  := fbDispatch.axFunction[FUNC_RETURN_TO_CARRY],
    xTeachCarry     := fbDispatch.axFunction[FUNC_TEACH_CARRY],
    xFloatTog       := fbDispatch.axFunction[FUNC_FLOAT_TOGGLE],
    xHeightLimTog   := fbDispatch.axFunction[FUNC_HEIGHT_LIM_TOGGLE],
    xTeachHeightLim := fbDispatch.axFunction[FUNC_TEACH_HEIGHT_LIM],
    xShake          := fbDispatch.axFunction[FUNC_BUCKET_SHAKE],
    rWorkDerate     := HAL.rWorkDerate,
    xEnable         := xLoaderEnable,
    rDt             := C_DT_MED );

(* =========================================================================
   6. Auxiliary hydraulics
   ========================================================================= *)
fbAux(
    rRocker         := HAL.rRightThumbRocker,
    stAttach        := stAttach,
    stProfile       := stProfile,
    xDetentEvent    := fbDispatch.axFunction[FUNC_AUX_DETENT],
    xHighFlowEvent  := fbDispatch.axFunction[FUNC_HIGH_FLOW_TOGGLE],
    rAuxPressureBar := HAL.rAuxPressureBar,
    rOilTempC       := HAL.rOilTempC,
    rEngineRpm      := HAL.rEngineRpm,
    rWorkDerate     := HAL.rWorkDerate,
    xEnable         := xLoaderEnable,
    rDt             := C_DT_MED );

(* =========================================================================
   6b. Payload weighing and load moment
   -------------------------------------------------------------------------
   The raise limit is applied ONLY to a positive (raise) lift command. Nothing
   here touches lowering, tilt or propel - lowering the load is the action that
   resolves an approaching tip, and it stays fully available at every margin.
   See the header of FB_LoadMoment.
   ========================================================================= *)
fbLoadMoment(
    rLiftPressureBar := HAL.rLiftPressureBar,
    rBoomAngleDeg    := HAL.rBoomAngleDeg,
    rBoomRateDegS    := fbLoader.rBoomRateDegS,
    rPitchDeg        := HAL.rImuPitchDeg,
    rRollDeg         := HAL.rImuRollDeg,
    rRearBallastLb   := HAL.rRearBallastLb,
    xEnable          := xLoaderEnable,
    rDt              := C_DT_MED );

(* =========================================================================
   7. Publish to the valve bank and the display
   ========================================================================= *)
IF fbLoader.rLiftOut > 0.0 THEN
    HAL.rPvgLiftCmd := fbLoader.rLiftOut * fbLoadMoment.rRaiseLimit;
ELSE
    HAL.rPvgLiftCmd := fbLoader.rLiftOut;
END_IF;
HAL.rPvgTiltCmd     := fbLoader.rTiltOut;
HAL.rPvgAuxCmd      := fbAux.rAuxCmd;
HAL.xLiftFloat      := fbLoader.xFloatOut;
HAL.xHighFlowValve  := fbAux.xHighFlowActive;

HAL.xIndSelfLevel   := fbLoader.xSelfLevelOn;
HAL.xIndAssist      := fbLoader.xAssistActive;
HAL.xIndHeightLimit := fbLoader.xAtHeightLimit;
HAL.xIndDetent      := fbAux.xDetentActive;
HAL.xIndHighFlow    := fbAux.xHighFlowActive;
HAL.xMsgHighFlowNo  := fbAux.xHighFlowDenied;
HAL.xMsgAuxPressure := fbAux.xPressureLimit;

HAL.rPayloadLb      := fbLoadMoment.rLastGoodLb;
HAL.xPayloadValid   := fbLoadMoment.xWeightValid;
HAL.rStabilityPct   := fbLoadMoment.rStabilityPct;
HAL.eStabilityWarn  := fbLoadMoment.eWarnLevel;
HAL.xMsgOverload    := fbLoadMoment.xOverload;
