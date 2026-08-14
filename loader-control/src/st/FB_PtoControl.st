(*
    FB_PtoControl.st

    Modulated engagement and supervision of the direct-drive rear PTO.

    ---------------------------------------------------------------------------
    SAFETY - read this before changing anything in this block

    PTO entanglement is among the most lethal hazards in agriculture, and it
    kills experienced operators, not careless ones. Two rules in this code are
    not preferences and must not be "improved" for convenience:

      1. THE PTO NEVER STARTS BY ITSELF. Not on sit-down, not on fault clear,
         not on engine restart, not when an inhibit goes away. Any inhibit
         drops the arming latch, and re-arming requires the operator to
         release the control and request engagement again. A machine whose
         PTO resumes when someone sits back down is a machine that kills
         somebody.

      2. OPERATOR OUT OF THE SEAT STOPS THE PTO, IMMEDIATELY. If a stationary
         PTO mode is ever added for augers or generators, it is a separate,
         deliberately awkward, clearly-indicated mode - never a relaxation of
         this path.

    As with propel, this block is the FUNCTIONAL layer. The rated stop must be
    a hardware path that cuts clutch pressure independently of this program,
    and there is a maximum permitted PTO stopping time after a stop command -
    the clutch alone will not meet it, so there is a brake in the mechanical
    design. See docs/05-rear-implement-architecture.md section 6.
    ---------------------------------------------------------------------------

    ENGAGEMENT. A wet clutch slammed into a 6 ft rotary cutter shocks the
    entire driveline - that inertia is why old tractors shear driveline pins.
    Engagement is therefore three phases:

      FILL      fast to the kiss point, taking up clearance while transmitting
                almost no torque
      MODULATE  ramp to lock over the implement's ramp time, PAUSING the ramp
                whenever the engine droops - so a heavy implement is brought
                up to speed as fast as the engine can stand and no faster
      LOCKED    full clamp

    The droop-aware pause is what makes this feel like a good tractor instead
    of a switch.
*)
FUNCTION_BLOCK FB_PtoControl
VAR_INPUT
    xEngageReq      : BOOL;    (* operator control - level, not a pulse       *)
    ePtoMode        : E_PtoMode := PTO_540;
    stImplement     : ST_ImplementProfile;

    rEngineRpm      : REAL;
    rEngineTargetRpm: REAL;
    rPtoShaftRpm    : REAL;    (* measured, from the PTO shaft pickup         *)

    rHitchPosition  : REAL;    (* 0..1, for auto-PTO                          *)
    xAutoPtoEnabled : BOOL := TRUE;

    xOperatorPresent: BOOL;    (* seat AND seat bar                           *)
    xEngineRunning  : BOOL;
    xEnable         : BOOL;
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    rClutchCmd      : REAL;    (* 0..1 to the proportional clutch valve       *)
    xPtoActive      : BOOL;
    ePtoState       : E_PtoState := PTO_OFF;
    eInhibit        : E_PtoInhibit := PTOINH_NEEDS_REQUEST;

    rEngineRpmForPto: REAL;    (* engine speed request to hold rated PTO      *)
    rPtoSlipPct     : REAL;    (* clutch slip, for display and diagnostics    *)
    xOverload       : BOOL;
END_VAR

VAR CONSTANT
    (* --- gear ratios: PTO revolutions per engine revolution --------------- *)
    C_RATIO_540     : REAL := 0.2455;   (* 540 rpm at 2200 engine rpm         *)
    C_RATIO_540E    : REAL := 0.3375;   (* 540 rpm at 1600 engine rpm         *)
    C_RATIO_1000    : REAL := 0.4545;   (* 1000 rpm at 2200 engine rpm        *)

    C_KISS_POINT    : REAL := 0.35;     (* clutch cmd at start of torque      *)
    C_FILL_TIME     : REAL := 0.30;     (* s, clearance take-up               *)

    (* Ramp pauses while the engine is drooping more than this. *)
    C_DROOP_HOLD    : REAL := 200.0;    (* rpm                                *)

    C_SLIP_WARN_PCT : REAL := 8.0;      (* locked clutch should not slip      *)
    C_SLIP_TRIP_PCT : REAL := 20.0;
    C_SLIP_TRIP_S   : REAL := 1.5;      (* sustained before we save the clutch*)

    C_AUTO_RAISE    : REAL := 0.70;     (* hitch above this -> PTO off        *)
    C_AUTO_LOWER    : REAL := 0.55;     (* hitch below this -> PTO may resume *)

    C_RATED_540     : REAL := 540.0;
    C_RATED_1000    : REAL := 1000.0;
END_VAR

VAR
    xArmed          : BOOL;    (* the anti-auto-restart latch - see header    *)
    xReqPrev        : BOOL;
    xAutoCut        : BOOL;    (* auto-PTO has the hitch raised               *)
    rRatio          : REAL;
    rExpectedPto    : REAL;
    rDroop          : REAL;
    rFillTimer      : REAL;
    rRampStep       : REAL;
    rSlipTimer      : REAL;
    xInhibited      : BOOL;
END_VAR

(* =========================================================================
   1. Gear ratio and engine speed target for the selected PTO mode
   ========================================================================= *)
CASE ePtoMode OF
    PTO_540:
        rRatio           := C_RATIO_540;
        rEngineRpmForPto := C_RATED_540 / C_RATIO_540;
    PTO_540E:
        rRatio           := C_RATIO_540E;
        rEngineRpmForPto := C_RATED_540 / C_RATIO_540E;
    PTO_1000:
        rRatio           := C_RATIO_1000;
        rEngineRpmForPto := C_RATED_1000 / C_RATIO_1000;
ELSE
    rRatio           := C_RATIO_540;
    rEngineRpmForPto := C_RATED_540 / C_RATIO_540;
END_CASE;

rExpectedPto := rEngineRpm * rRatio;

(* =========================================================================
   2. Clutch slip measurement
   -------------------------------------------------------------------------
   A locked wet clutch should turn at the gear ratio. Persistent slip means
   it is burning itself up, either from a jammed implement or a worn pack.
   ========================================================================= *)
IF rExpectedPto > 50.0 THEN
    rPtoSlipPct := 100.0 * (rExpectedPto - rPtoShaftRpm) / rExpectedPto;
    IF rPtoSlipPct < 0.0 THEN rPtoSlipPct := 0.0; END_IF;
ELSE
    rPtoSlipPct := 0.0;
END_IF;

IF ePtoState = PTO_LOCKED AND rPtoSlipPct > C_SLIP_TRIP_PCT THEN
    rSlipTimer := rSlipTimer + rDt;
ELSE
    rSlipTimer := 0.0;
END_IF;

xOverload := (ePtoState = PTO_LOCKED) AND (rPtoSlipPct > C_SLIP_WARN_PCT);

(* =========================================================================
   3. Auto-PTO
   -------------------------------------------------------------------------
   Stop the PTO when the implement is lifted out of work for a headland turn,
   resume when it is set back down. Hysteresis so a hitch hunting near the
   threshold does not cycle the clutch.

   Note this is NOT a relaxation of rule 1: auto-PTO can only resume a PTO the
   operator has already requested and never released. Releasing the control
   drops xArmed and auto-PTO cannot re-arm it.
   ========================================================================= *)
IF xAutoPtoEnabled AND stImplement.xAutoPto THEN
    IF rHitchPosition > C_AUTO_RAISE THEN
        xAutoCut := TRUE;
    ELSIF rHitchPosition < C_AUTO_LOWER THEN
        xAutoCut := FALSE;
    END_IF;
ELSE
    xAutoCut := FALSE;
END_IF;

(* =========================================================================
   4. Inhibits
   ========================================================================= *)
IF NOT xEnable OR NOT xOperatorPresent THEN
    eInhibit := PTOINH_NO_OPERATOR;
ELSIF NOT xEngineRunning THEN
    eInhibit := PTOINH_ENGINE_OFF;
ELSIF rSlipTimer > C_SLIP_TRIP_S THEN
    eInhibit := PTOINH_CLUTCH_SLIP;
ELSIF xAutoCut THEN
    eInhibit := PTOINH_AUTO_RAISED;
ELSIF NOT xArmed THEN
    eInhibit := PTOINH_NEEDS_REQUEST;
ELSE
    eInhibit := PTOINH_NONE;
END_IF;

(* A hard inhibit drops the arming latch. PTOINH_AUTO_RAISED deliberately does
   NOT - that is the one condition the operator expects to clear by itself,
   and it only ever occurs while they are holding the control on. *)
xInhibited := (eInhibit <> PTOINH_NONE) AND (eInhibit <> PTOINH_AUTO_RAISED);

IF xInhibited THEN
    xArmed := FALSE;
END_IF;

(* Re-arm ONLY on a fresh rising edge of the request with nothing inhibiting.
   This is rule 1 from the header, and it is the whole reason the latch
   exists. *)
IF xEngageReq AND NOT xReqPrev
   AND xEnable AND xOperatorPresent AND xEngineRunning
   AND rSlipTimer <= C_SLIP_TRIP_S THEN
    xArmed := TRUE;
END_IF;

IF NOT xEngageReq THEN
    xArmed := FALSE;         (* releasing the control always disarms *)
END_IF;

xReqPrev := xEngageReq;

(* =========================================================================
   5. Engagement state machine
   ========================================================================= *)
IF NOT xArmed OR xInhibited OR xAutoCut THEN
    (* Disengage immediately. No ramp down - a PTO stop is a stop. *)
    ePtoState   := PTO_OFF;
    rClutchCmd  := 0.0;
    rFillTimer  := 0.0;
    IF rSlipTimer > C_SLIP_TRIP_S THEN
        ePtoState := PTO_FAULT;
    END_IF;

ELSE
    CASE ePtoState OF

        PTO_OFF, PTO_FAULT:
            ePtoState  := PTO_FILL;
            rFillTimer := 0.0;
            rClutchCmd := 0.0;

        PTO_FILL:
            (* Fast to the kiss point - clearance take-up, negligible torque *)
            rFillTimer := rFillTimer + rDt;
            rClutchCmd := C_KISS_POINT * rFillTimer / C_FILL_TIME;
            IF rClutchCmd > C_KISS_POINT THEN
                rClutchCmd := C_KISS_POINT;
            END_IF;
            IF rFillTimer >= C_FILL_TIME THEN
                ePtoState := PTO_MODULATE;
            END_IF;

        PTO_MODULATE:
            (* Ramp to lock over the implement's ramp time - but hold station
               whenever the engine is drooping, so a high-inertia implement is
               spun up as fast as the engine can stand and no faster. This is
               anti-stall for the clutch. *)
            rDroop := rEngineTargetRpm - rEngineRpm;

            IF rDroop < C_DROOP_HOLD THEN
                IF stImplement.rPtoRampS > 0.1 THEN
                    rRampStep := (1.0 - C_KISS_POINT) * rDt / stImplement.rPtoRampS;
                ELSE
                    rRampStep := 1.0;
                END_IF;
                rClutchCmd := rClutchCmd + rRampStep;
            END_IF;

            IF rClutchCmd >= 1.0 THEN
                rClutchCmd := 1.0;
                ePtoState  := PTO_LOCKED;
            END_IF;

        PTO_LOCKED:
            rClutchCmd := 1.0;

    END_CASE;
END_IF;

xPtoActive := (ePtoState = PTO_MODULATE) OR (ePtoState = PTO_LOCKED);

IF rClutchCmd < 0.0 THEN rClutchCmd := 0.0; END_IF;
IF rClutchCmd > 1.0 THEN rClutchCmd := 1.0; END_IF;
