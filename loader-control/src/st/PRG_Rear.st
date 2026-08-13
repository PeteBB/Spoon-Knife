(*
    PRG_Rear.st

    50 ms task: three-point hitch, PTO, headland sequencing and rear remotes.

    Chain:

        headland button ──► FB_HeadlandSequence ──┬──► hitch raise/lower pulses
                                                  └──► PTO request (gated)
                                                            │
        depth dial ──────────────────────────────────────┐  │
        draft sensor ────────────────────────────────────┤  │
        slip from FB_TractiveControl ────────────────────┤  │
                                                         ▼  ▼
                                            FB_HitchControl   FB_PtoControl
                                                    │               │
                                            PVG hitch section   clutch valve

    The slip input crossing from the propel task into the hitch loop is the
    novel connection on this machine - see
    docs/05-rear-implement-architecture.md section 7.
*)
PROGRAM PRG_Rear
VAR
    fbHitch     : FB_HitchControl;
    fbPto       : FB_PtoControl;
    fbHeadland  : FB_HeadlandSequence;

    stImplement : ST_ImplementProfile;

    xRearEnable : BOOL;
    xPtoGated   : BOOL;
    xRaisePulse : BOOL;
    xLowerPulse : BOOL;
END_VAR

(* --- implement profile, from the ISOBUS node or the display selection ----- *)
IF HAL.xImplementChanged THEN
    stImplement := HAL.stImplementProfile;
END_IF;

xRearEnable := HAL.xSeatSwitch AND HAL.xSeatBarDown AND HAL.xEngineRunning;

(* =========================================================================
   1. Headland sequencer
   ========================================================================= *)
fbHeadland(
    xTrigger          := HAL.xHeadlandButton,
    xSequenceOn       := HAL.xHeadlandEnabled,
    rHitchPosition    := HAL.rHitchPosition,
    rPtoShaftRpm      := HAL.rPtoShaftRpm,
    rPtoTargetRpm     := fbPto.rEngineRpmForPto * 0.2455,
    xImplementUsesPto := stImplement.xUsesPto,
    xEnable           := xRearEnable,
    rDt               := C_DT_MED );

(* Manual controls and the sequencer both drive the hitch. *)
xRaisePulse := HAL.xHitchRaiseBtn OR fbHeadland.xHitchRaise;
xLowerPulse := HAL.xHitchLowerBtn OR fbHeadland.xHitchLower;

(* =========================================================================
   2. Hitch
   -------------------------------------------------------------------------
   rSlipRatio comes across from the propel task. The hitch tries weight
   transfer BEFORE FB_TractiveControl resorts to cutting rimpull - lifting the
   implement a little is a far better answer than refusing to pull.
   ========================================================================= *)
fbHitch(
    rDepthSetpoint  := HAL.rHitchDepthDial,
    rHitchPosition  := HAL.rHitchPosition,
    rDraftForce     := HAL.rDraftForce,
    rDraftSetpoint  := HAL.rDraftDial,
    rDraftBlend     := stImplement.rDraftBlend,
    rSlipRatio      := HAL.rSlipRatioMax,
    xSlipAssistOn   := HAL.xSlipAssistEnabled,
    xRaiseReq       := xRaisePulse,
    xLowerReq       := xLowerPulse,
    rDropRate       := stImplement.rDropRate,
    rHeightLimit    := HAL.rHitchHeightLimit,
    xEnable         := xRearEnable,
    rDt             := C_DT_MED );

(* =========================================================================
   3. PTO
   -------------------------------------------------------------------------
   The operator's PTO switch is ANDed with the sequencer's request. The
   sequencer can only ever stop a PTO the operator has already asked for - it
   can never start one. Turning the switch off always wins.
   ========================================================================= *)
xPtoGated := HAL.xPtoSwitch AND fbHeadland.xPtoRequest;

fbPto(
    xEngageReq       := xPtoGated,
    ePtoMode         := HAL.ePtoMode,
    stImplement      := stImplement,
    rEngineRpm       := HAL.rEngineRpm,
    rEngineTargetRpm := HAL.rEngineTargetRpm,
    rPtoShaftRpm     := HAL.rPtoShaftRpm,
    rHitchPosition   := HAL.rHitchPosition,
    xAutoPtoEnabled  := HAL.xAutoPtoEnabled,
    xOperatorPresent := HAL.xSeatSwitch AND HAL.xSeatBarDown,
    xEngineRunning   := HAL.xEngineRunning,
    xEnable          := xRearEnable,
    rDt              := C_DT_MED );

(* =========================================================================
   4. Publish
   ========================================================================= *)
HAL.rPvgHitchCmd     := fbHitch.rHitchCmd;
HAL.rPtoClutchCmd    := fbPto.rClutchCmd;

(* Engine speed to hold rated PTO. Only requested when the PTO is actually
   turning - otherwise the machine would sit at 2200 rpm all day because a
   switch is on. *)
IF fbPto.xPtoActive THEN
    HAL.rPtoEngineRequest := fbPto.rEngineRpmForPto;
ELSE
    HAL.rPtoEngineRequest := 0.0;
END_IF;

HAL.xIndPtoActive    := fbPto.xPtoActive;
HAL.ePtoState        := fbPto.ePtoState;
HAL.ePtoInhibit      := fbPto.eInhibit;
HAL.rPtoSlipPct      := fbPto.rPtoSlipPct;
HAL.xMsgPtoOverload  := fbPto.xOverload;

HAL.rHitchTarget     := fbHitch.rTargetPosition;
HAL.xIndDraftActive  := fbHitch.xDraftActive;
HAL.xIndSlipAssist   := fbHitch.xSlipAssist;
HAL.xIndTransport    := fbHitch.xInTransport;
HAL.eHeadlandState   := fbHeadland.eState;
HAL.xIndSequencing   := fbHeadland.xSequencing;
