(*
    FB_HitchControl.st

    Three-point hitch: position control, draft control, and the slip-referenced
    draft augmentation that is unique to this machine.

    ---------------------------------------------------------------------------
    WHY THIS IS BETTER THAN A TRACTOR'S DRAFT CONTROL

    Classic Ferguson draft control measures the PULL on the implement and
    raises the hitch as draft rises, transferring implement weight onto the
    tractor to restore traction. Every tractor since 1940 does a version of it.

    But draft force is only a PROXY for what the operator actually cares
    about, which is slip. Tractors measure draft because measuring slip was
    impossible in 1940.

    This machine already measures slip - FB_TractiveControl computes it for the
    rimpull limiting. So the loop can close on the real variable:

        slip rises -> raise the hitch -> weight transfers to the tracks ->
        slip falls -> hitch returns to the commanded depth

    Both loops run. The draft term gives behaviour a tractor operator
    recognises immediately and reaches for by instinct; the slip term corrects
    on the variable that actually governs whether work is getting done. Where
    they disagree, the slip term is the one telling the truth.
    ---------------------------------------------------------------------------

    Position convention: 0.0 = fully lowered, 1.0 = fully raised.
*)
FUNCTION_BLOCK FB_HitchControl
VAR_INPUT
    rDepthSetpoint  : REAL;   (* 0..1 operator depth dial                     *)
    rHitchPosition  : REAL;   (* 0..1 measured, from the rockshaft sensor     *)

    rDraftForce     : REAL;   (* 0..1 normalised, from the link pin sensors   *)
    rDraftSetpoint  : REAL := 0.6;  (* draft the operator is willing to pull  *)
    rDraftBlend     : REAL := 0.0;  (* 0 = pure position .. 1 = full draft    *)

    rSlipRatio      : REAL;   (* 0..1 from FB_TractiveControl                 *)
    xSlipAssistOn   : BOOL := TRUE;

    xRaiseReq       : BOOL;   (* pulse - lift out of work, to transport       *)
    xLowerReq       : BOOL;   (* pulse - return to the remembered depth       *)

    rDropRate       : REAL := 0.5;  (* 0.05..1, lowering speed limit          *)
    rHeightLimit    : REAL := 1.0;  (* transport height, 0..1                 *)

    xEnable         : BOOL;
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rHitchCmd       : REAL;   (* -1..+1 to the PVG section, + = raise         *)
    xInTransport    : BOOL;
    xDraftActive    : BOOL;
    xSlipAssist     : BOOL;   (* slip term is currently lifting the hitch     *)
    rTargetPosition : REAL;   (* for the display                              *)
END_VAR

VAR CONSTANT
    (* --- CALIBRATION VALUES ---------------------------------------------- *)
    C_POS_KP        : REAL := 3.2;    (* position loop proportional gain      *)
    C_POS_KI        : REAL := 0.8;
    C_POS_DEADBAND  : REAL := 0.012;  (* stops the hitch hunting              *)
    C_POS_MAX       : REAL := 1.0;

    C_DRAFT_GAIN    : REAL := 0.55;   (* position units per unit draft error  *)
    C_DRAFT_MAX     : REAL := 0.35;   (* how far draft may lift the hitch     *)

    (* Slip term. The threshold sits deliberately BELOW the point at which
       FB_TractiveControl starts cutting rimpull, so the hitch tries weight
       transfer first. Cutting tractive effort is the blunter instrument and
       should be the second resort, not the first. *)
    C_SLIP_THRESH   : REAL := 0.12;
    C_SLIP_GAIN     : REAL := 1.6;
    C_SLIP_MAX      : REAL := 0.40;
    C_SLIP_DECAY_S  : REAL := 2.5;    (* how fast the slip lift washes out    *)

    C_WORK_WINDOW   : REAL := 0.10;   (* "at working depth" tolerance         *)
END_VAR

VAR
    rWorkingDepth   : REAL := 0.30;   (* remembered depth for quick-lower     *)
    rDraftErr       : REAL;
    rDraftCorr      : REAL;
    rSlipErr        : REAL;
    rSlipCorr       : REAL;
    rSlipCorrHeld   : REAL;
    rPosErr         : REAL;
    rInt            : REAL;
    rCmd            : REAL;
    rLowerLimit     : REAL;
END_VAR

(* =========================================================================
   0. Disabled - park the valve, hold state
   ========================================================================= *)
IF NOT xEnable THEN
    rHitchCmd     := 0.0;
    rInt          := 0.0;
    rSlipCorrHeld := 0.0;
    xDraftActive  := FALSE;
    xSlipAssist   := FALSE;
    RETURN;
END_IF;

(* =========================================================================
   1. Transport / work toggle
   -------------------------------------------------------------------------
   Raising remembers the depth being worked so that lowering returns to it
   exactly. An operator who has spent ten minutes dialling in a depth should
   not have to find it again after every headland turn.
   ========================================================================= *)
IF xRaiseReq THEN
    IF NOT xInTransport THEN
        rWorkingDepth := rDepthSetpoint;
    END_IF;
    xInTransport := TRUE;
END_IF;

IF xLowerReq THEN
    xInTransport := FALSE;
END_IF;

(* =========================================================================
   2. Target position
   ========================================================================= *)
IF xInTransport THEN
    rTargetPosition := rHeightLimit;
    xDraftActive    := FALSE;
    xSlipAssist     := FALSE;
    rSlipCorrHeld   := 0.0;

ELSE
    (* --- draft term: pulling harder than asked -> lift a little --------- *)
    rDraftErr := rDraftForce - rDraftSetpoint;
    IF rDraftErr < 0.0 THEN
        rDraftErr := 0.0;          (* only ever lifts, never forces down *)
    END_IF;

    rDraftCorr := C_DRAFT_GAIN * rDraftErr * rDraftBlend;
    IF rDraftCorr > C_DRAFT_MAX THEN rDraftCorr := C_DRAFT_MAX; END_IF;

    xDraftActive := (rDraftBlend > 0.05) AND (rDraftCorr > 0.01);

    (* --- slip term: the variable that actually matters ------------------ *)
    IF xSlipAssistOn THEN
        rSlipErr := rSlipRatio - C_SLIP_THRESH;
        IF rSlipErr < 0.0 THEN rSlipErr := 0.0; END_IF;

        rSlipCorr := C_SLIP_GAIN * rSlipErr;
        IF rSlipCorr > C_SLIP_MAX THEN rSlipCorr := C_SLIP_MAX; END_IF;

        (* Rise fast, wash out slowly. Snapping the hitch back down the
           instant slip clears just re-buries the implement and starts the
           cycle again - the hunting that gives draft control a bad name. *)
        IF rSlipCorr > rSlipCorrHeld THEN
            rSlipCorrHeld := rSlipCorr;
        ELSE
            rSlipCorrHeld := rSlipCorrHeld - rDt * C_SLIP_MAX / C_SLIP_DECAY_S;
            IF rSlipCorrHeld < 0.0 THEN rSlipCorrHeld := 0.0; END_IF;
        END_IF;

        xSlipAssist := rSlipCorrHeld > 0.01;
    ELSE
        rSlipCorrHeld := 0.0;
        xSlipAssist   := FALSE;
    END_IF;

    rTargetPosition := rDepthSetpoint + rDraftCorr + rSlipCorrHeld;
END_IF;

IF rTargetPosition > rHeightLimit THEN rTargetPosition := rHeightLimit; END_IF;
IF rTargetPosition < 0.0          THEN rTargetPosition := 0.0;          END_IF;

(* =========================================================================
   3. Position loop
   ========================================================================= *)
rPosErr := rTargetPosition - rHitchPosition;

IF ABS(rPosErr) < C_POS_DEADBAND THEN
    (* In the deadband the valve is parked and the integrator is frozen -
       otherwise it winds up against a hitch that is already where it was
       asked to be, and the next command arrives as a lurch. *)
    rCmd := 0.0;
ELSE
    rInt := rInt + rPosErr * rDt;

    (* Anti-windup *)
    IF rInt * C_POS_KI >  C_POS_MAX THEN rInt :=  C_POS_MAX / C_POS_KI; END_IF;
    IF rInt * C_POS_KI < -C_POS_MAX THEN rInt := -C_POS_MAX / C_POS_KI; END_IF;

    rCmd := C_POS_KP * rPosErr + C_POS_KI * rInt;
END_IF;

(* =========================================================================
   4. Rate of drop
   -------------------------------------------------------------------------
   Lowering is gravity-assisted and will slam an implement into the ground at
   full valve opening. Raising is pump-limited and needs no equivalent limit.
   ========================================================================= *)
rLowerLimit := rDropRate;
IF rLowerLimit < 0.05 THEN rLowerLimit := 0.05; END_IF;
IF rLowerLimit > 1.0  THEN rLowerLimit := 1.0;  END_IF;

IF rCmd < -rLowerLimit THEN
    rCmd := -rLowerLimit;
END_IF;

IF rCmd >  C_POS_MAX THEN rCmd :=  C_POS_MAX; END_IF;
IF rCmd < -C_POS_MAX THEN rCmd := -C_POS_MAX; END_IF;

rHitchCmd := rCmd;
