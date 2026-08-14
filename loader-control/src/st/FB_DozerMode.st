(*
    FB_DozerMode.st

    Load-path awareness for the dozer blade with a frame push link.

    ---------------------------------------------------------------------------
    WHAT THIS BLOCK IS, AND WHAT IT IS NOT

    The blade mounts on the quick-attach plate and ALSO ties back to a lower
    push point on the frame through a slotted link, so that horizontal thrust
    goes into the frame instead of twisting the loader arms.

    Because the arms swing through an arc and the frame does not move, the
    linkage would be over-constrained if both connections were rigid. The slot
    resolves that mechanically: the pin slides as the arms rise, and at the top
    of the slot it simply RUNS OUT. Nothing binds, nothing yields - the machine
    just loses push assist.

    THIS BLOCK IS NOT THE STRUCTURAL PROTECTION. The slot geometry and the
    mechanical backstop are. If this block did not exist, raising the arms would
    disengage the link harmlessly; the machine would push through the arms and
    an operator could eventually overload them, but nothing would break the
    moment a sensor failed.

    That distinction is the whole design. A structural limit enforced only by
    application software is one dirty connector away from tearing the machine
    apart - see docs/08-dozer-attachment-integration.md section 2. Software
    optimises inside the mechanism's envelope. The mechanism enforces it.

    ---------------------------------------------------------------------------
    WHAT IT ACTUALLY DOES

    It knows which load path is carrying thrust, and schedules the rimpull
    ceiling accordingly:

        arms low, pin in slot   -> thrust into the frame  -> FULL rimpull
        arms near slot top      -> handing over           -> fading
        arms above slot         -> thrust into the arms   -> LIMITED rimpull

    Note what is NOT restricted: lift. The operator can raise the blade over a
    windrow, over an obstacle, to back-drag at height - any time they like. The
    machine simply declines to generate force the arms cannot carry while it is
    up there.

    That is a better answer than blocking lift, because it never removes a
    motion the operator needs, and because it protects against the thing that
    actually does damage: high FORCE, not high POSITION.

    ---------------------------------------------------------------------------
    FAIL RESTRICTIVE

    Dozer detected but the profile did not load? Boom angle implausible? Link
    sensor disagreeing with the geometry? Assume the WEAK load path.

    A machine that quietly reverts to full push force when a sensor drops out is
    a machine that breaks itself. Doubt resolves toward the conservative
    configuration, every time, and the operator gets a message explaining the
    reduced performance rather than discovering it as a bent arm.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_DozerMode
VAR_INPUT
    stAttach        : ST_AttachmentProfile;
    xProfileValid   : BOOL;   (* attachment ID read cleanly                   *)

    rBoomAngleDeg   : REAL;
    xBoomAngleValid : BOOL;   (* sensor plausibility from the HAL             *)

    xPushLinkSensor : BOOL;   (* proximity on the link: TRUE = pin engaged    *)
    xLinkSensorFitted : BOOL := TRUE;

    xEnable         : BOOL;
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rRimpullScale   : REAL := 1.0;  (* multiplier on the rimpull setting      *)
    rRaiseLimit     : REAL := 1.0;  (* only bites when the slot is untrusted  *)
    ePushRegime     : E_PushRegime := PUSH_NONE;

    xDozerActive    : BOOL;
    xLinkFault      : BOOL;   (* sensor and geometry disagree                 *)
    xConfigFault    : BOOL;   (* dozer fitted, configuration not trustworthy  *)
    xMsgReducedPush : BOOL;   (* display: "reduced push - blade raised"       *)
END_VAR

VAR CONSTANT
    C_LINK_DISAGREE_S : REAL := 1.0;   (* debounce before calling it a fault  *)
    C_ANGLE_MIN_VALID : REAL := -25.0;
    C_ANGLE_MAX_VALID : REAL := 95.0;

    (* Used only when the slot itself cannot be trusted - a hard-ish ceiling
       on raise, faded rather than stepped. In normal operation this never
       bites, because the slot handles the geometry. *)
    C_UNTRUSTED_FADE  : REAL := 8.0;   (* deg below slot top                  *)
END_VAR

VAR
    rSlotTop     : REAL;
    rFadeBand    : REAL;
    rArmsMax     : REAL;
    xExpectEngaged : BOOL;
    rDisagreeTimer : REAL;
    rFadePos     : REAL;
    xAngleOk     : BOOL;
END_VAR

(* =========================================================================
   0. No dozer fitted - pass everything through untouched
   ========================================================================= *)
IF NOT xEnable OR NOT stAttach.xIsDozer THEN
    rRimpullScale   := 1.0;
    rRaiseLimit     := 1.0;
    ePushRegime     := PUSH_NONE;
    xDozerActive    := FALSE;
    xLinkFault      := FALSE;
    xConfigFault    := FALSE;
    xMsgReducedPush := FALSE;
    rDisagreeTimer  := 0.0;
    RETURN;
END_IF;

xDozerActive := TRUE;

rSlotTop  := stAttach.rSlotTopDeg;
rFadeBand := stAttach.rSlotFadeDeg;
rArmsMax  := stAttach.rArmsRimpullMax;

IF rFadeBand < 1.0 THEN rFadeBand := 1.0; END_IF;
IF rArmsMax  < 0.1 THEN rArmsMax  := 0.1; END_IF;
IF rArmsMax  > 1.0 THEN rArmsMax  := 1.0; END_IF;

(* =========================================================================
   1. Is the boom angle believable?
   ========================================================================= *)
xAngleOk := xBoomAngleValid
        AND rBoomAngleDeg > C_ANGLE_MIN_VALID
        AND rBoomAngleDeg < C_ANGLE_MAX_VALID;

(* =========================================================================
   2. Cross-check the link sensor against the geometry
   -------------------------------------------------------------------------
   Geometry says where the pin SHOULD be. The sensor says where it IS. Sustained
   disagreement means something is bent, worn or mis-installed - which is
   exactly the condition worth reporting before it becomes a failure.
   ========================================================================= *)
xExpectEngaged := xAngleOk AND (rBoomAngleDeg < rSlotTop);

IF xLinkSensorFitted AND xAngleOk THEN
    IF xPushLinkSensor <> xExpectEngaged THEN
        rDisagreeTimer := rDisagreeTimer + rDt;
    ELSE
        rDisagreeTimer := 0.0;
    END_IF;
    xLinkFault := rDisagreeTimer > C_LINK_DISAGREE_S;
ELSE
    rDisagreeTimer := 0.0;
    xLinkFault     := FALSE;
END_IF;

(* =========================================================================
   3. Anything untrustworthy -> assume the weak load path
   ========================================================================= *)
xConfigFault := (NOT xProfileValid) OR (NOT xAngleOk) OR xLinkFault;

IF xConfigFault THEN
    ePushRegime   := PUSH_CONSERVATIVE;
    rRimpullScale := rArmsMax;

    (* The slot cannot be trusted either, so this is the one case where lift
       IS limited - faded in over C_UNTRUSTED_FADE degrees below the nominal
       slot top. Still never a hard block: the operator keeps the ability to
       raise, just slowly and with a message on the screen. *)
    IF xAngleOk THEN
        rFadePos := (rSlotTop - rBoomAngleDeg) / C_UNTRUSTED_FADE;
        IF rFadePos < 0.15 THEN rFadePos := 0.15; END_IF;
        IF rFadePos > 1.0  THEN rFadePos := 1.0;  END_IF;
        rRaiseLimit := rFadePos;
    ELSE
        rRaiseLimit := 0.30;    (* no usable angle - slow, but not blocked *)
    END_IF;

    xMsgReducedPush := TRUE;
    RETURN;
END_IF;

(* =========================================================================
   4. Normal operation - schedule rimpull against boom height
   ========================================================================= *)
rRaiseLimit := 1.0;         (* the slot handles the geometry; lift is free *)

IF rBoomAngleDeg <= (rSlotTop - rFadeBand) THEN
    (* Pin solidly in the slot: thrust goes into the frame. Push away. *)
    ePushRegime   := PUSH_FRAME;
    rRimpullScale := 1.0;

ELSIF rBoomAngleDeg >= rSlotTop THEN
    (* Pin out of the slot: the arms are carrying thrust now. *)
    ePushRegime   := PUSH_ARMS;
    rRimpullScale := rArmsMax;

ELSE
    (* Hand-over band. Fade rather than step - a rimpull ceiling that drops
       instantly mid-push feels like the machine hit something. *)
    ePushRegime := PUSH_TRANSITION;
    rFadePos    := (rSlotTop - rBoomAngleDeg) / rFadeBand;
    IF rFadePos < 0.0 THEN rFadePos := 0.0; END_IF;
    IF rFadePos > 1.0 THEN rFadePos := 1.0; END_IF;
    rRimpullScale := rArmsMax + rFadePos * (1.0 - rArmsMax);
END_IF;

xMsgReducedPush := (ePushRegime = PUSH_ARMS) OR (ePushRegime = PUSH_TRANSITION);
