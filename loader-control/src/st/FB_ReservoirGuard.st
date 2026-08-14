(*
    FB_ReservoirGuard.st

    Hydraulic reservoir level supervision: temperature compensation, staged
    protection, slow-leak detection and a pre-connect volume check.

    ---------------------------------------------------------------------------
    THE FAILURE MODE THIS EXISTS FOR

    An attachment sits disconnected. Flat-face couplers seal the machine side,
    so the machine loses nothing - but the attachment weeps its own trapped
    charge out through a tired hose or fitting. The operator reconnects, and the
    attachment's motor, hoses and lines refill FROM THE MACHINE'S RESERVOIR.
    Two or three gallons on a big high-flow head.

    The machine is now low, and nobody finds out until something is damaged.

    ---------------------------------------------------------------------------
    TEMPERATURE COMPENSATION COMES FIRST, AND IT IS NOT OPTIONAL

    Hydraulic oil expands appreciably with temperature - roughly 0.07% of volume
    per degree C. Across a 60 degree working swing that is over 4% of tank
    level, which is the same order as the gap between "fine" and "warn".

    An uncompensated low-level alarm cries wolf every cold morning. The operator
    learns within a week that the warning means nothing, and from then on the
    alarm is worse than useless - it has trained them to ignore the one message
    that will eventually matter. Compensate, or do not fit the feature.

    ---------------------------------------------------------------------------
    THE ASYMMETRY IN THE STAGED RESPONSE

        LOW       warn clearly, keep working
        CRITICAL  cut aux and work hydraulics, but DO NOT cut propel

    Running a pump with air ingestion destroys it, so shutting off the big flow
    consumers is right. But stranding the machine in the middle of a field is
    also a real cost, and the operator needs to get it onto a trailer.

    So mobility survives, at reduced speed, with the display shouting. Same
    principle as never blocking the lowering of a raised load: keep available
    the action that lets the operator RESOLVE the situation. Confirm the
    specific thresholds with the hydraulics supplier - the balance between pump
    protection and stranding is a judgement call, not a calculation.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_ReservoirGuard
VAR_INPUT
    rLevelRawPct    : REAL;   (* 0..100 from the tank level sensor            *)
    rOilTempC       : REAL;

    (* Expected fill volume of the attachment about to be connected, from its
       profile. Zero for unknown or dumb attachments. *)
    rAttachFillGal  : REAL;
    xAttachCoupling : BOOL;   (* attachment being coupled - suppress leak calc *)

    xEnable         : BOOL;
    rDt             : REAL := 0.200;
END_VAR

VAR_OUTPUT
    rLevelPct       : REAL;   (* temperature compensated                      *)
    rUsableGal      : REAL;
    eLevelState     : E_LevelState := LVL_OK;

    xInhibitAux     : BOOL;
    xInhibitWork    : BOOL;
    rPropelLimit    : REAL := 1.0;   (* never reaches zero - see header       *)

    rLossRateGalHr  : REAL;
    xMsgLeak        : BOOL;   (* sustained loss - investigate                 *)
    xMsgPreConnect  : BOOL;   (* connecting this will put you below minimum   *)
    xMsgAddOil      : BOOL;
END_VAR

VAR CONSTANT
    (* --- CALIBRATION ------------------------------------------------------ *)
    C_RESERVOIR_GAL   : REAL := 22.0;    (* usable tank volume                *)

    C_LOW_PCT         : REAL := 35.0;
    C_CRIT_PCT        : REAL := 20.0;
    C_MIN_SAFE_PCT    : REAL := 25.0;    (* floor used by the pre-connect check *)

    (* Volumetric expansion of hydraulic oil, expressed as percent of tank
       level per degree C. ~0.0007/C -> 0.07 %/C. *)
    C_EXPAND_PCT_PER_C : REAL := 0.070;
    C_REF_TEMP_C       : REAL := 40.0;

    (* --- leak detection --------------------------------------------------- *)
    C_LEAK_WINDOW_S    : REAL := 600.0;  (* 10 minutes between samples        *)
    C_LEAK_RATE_GALHR  : REAL := 0.25;   (* sustained loss above this = leak  *)
    C_LEAK_CONFIRMS    : INT  := 2;      (* consecutive windows before alarm  *)
    C_COUPLE_SUPPRESS_S: REAL := 300.0;  (* after coupling, expect a drop     *)

    C_PROPEL_LIMIT_CRIT: REAL := 0.35;   (* enough to drive onto a trailer    *)
END_VAR

VAR
    rComp        : REAL;
    rWindowTimer : REAL;
    rRefLevel    : REAL;
    rSuppress    : REAL;
    iLeakCount   : INT;
    rDropPct     : REAL;
    xInit        : BOOL;
END_VAR

IF NOT xEnable THEN
    xInhibitAux    := FALSE;
    xInhibitWork   := FALSE;
    rPropelLimit   := 1.0;
    xMsgLeak       := FALSE;
    xMsgPreConnect := FALSE;
    xMsgAddOil     := FALSE;
    RETURN;
END_IF;

(* =========================================================================
   1. Temperature compensation - see the header
   -------------------------------------------------------------------------
   Hot oil has expanded, so the sensor reads high; subtract the expansion to
   get back to a reference-temperature level that thresholds can be set
   against. Cold oil reads low and gets corrected upward, which is precisely
   the cold-morning false alarm this prevents.
   ========================================================================= *)
rComp := rLevelRawPct - C_EXPAND_PCT_PER_C * (rOilTempC - C_REF_TEMP_C);

IF rComp > 100.0 THEN rComp := 100.0; END_IF;
IF rComp < 0.0   THEN rComp := 0.0;   END_IF;

rLevelPct  := rComp;
rUsableGal := C_RESERVOIR_GAL * rComp / 100.0;

IF NOT xInit THEN
    rRefLevel := rComp;
    xInit     := TRUE;
END_IF;

(* =========================================================================
   2. Staged state
   ========================================================================= *)
IF rComp <= C_CRIT_PCT THEN
    eLevelState := LVL_CRITICAL;
ELSIF rComp <= C_LOW_PCT THEN
    eLevelState := LVL_LOW;
ELSE
    eLevelState := LVL_OK;
END_IF;

CASE eLevelState OF
    LVL_OK:
        xInhibitAux  := FALSE;
        xInhibitWork := FALSE;
        rPropelLimit := 1.0;
        xMsgAddOil   := FALSE;

    LVL_LOW:
        (* Warn only. Cutting function here would be over-reaction and would
           teach the operator to distrust the next warning. *)
        xInhibitAux  := FALSE;
        xInhibitWork := FALSE;
        rPropelLimit := 1.0;
        xMsgAddOil   := TRUE;

    LVL_CRITICAL:
        (* Cut the big flow consumers to protect the pumps from aeration, but
           leave the machine able to drive itself off the field. *)
        xInhibitAux  := TRUE;
        xInhibitWork := TRUE;
        rPropelLimit := C_PROPEL_LIMIT_CRIT;
        xMsgAddOil   := TRUE;
END_CASE;

(* =========================================================================
   3. Pre-connect volume check
   -------------------------------------------------------------------------
   The direct answer to the failure mode in the header: tell the operator
   BEFORE they couple, not after the machine has already given up three
   gallons to fill a drained attachment.
   ========================================================================= *)
IF rAttachFillGal > 0.1 THEN
    xMsgPreConnect := ((rUsableGal - rAttachFillGal) / C_RESERVOIR_GAL * 100.0)
                      < C_MIN_SAFE_PCT;
ELSE
    xMsgPreConnect := FALSE;
END_IF;

(* =========================================================================
   4. Slow-leak detection
   -------------------------------------------------------------------------
   Sampled comparison over a long window. A weep that would otherwise be
   discovered as a seized pump becomes a message on the screen a week earlier,
   and it costs one sensor that is being fitted anyway.

   Two things must NOT look like leaks: coupling an attachment (a legitimate
   large drop) and topping up the tank (a rise).
   ========================================================================= *)
IF xAttachCoupling THEN
    rSuppress := C_COUPLE_SUPPRESS_S;
ELSIF rSuppress > 0.0 THEN
    rSuppress := rSuppress - rDt;
END_IF;

rWindowTimer := rWindowTimer + rDt;

IF rWindowTimer >= C_LEAK_WINDOW_S THEN
    rDropPct := rRefLevel - rComp;

    IF rDropPct > 0.0 THEN
        rLossRateGalHr := (rDropPct / 100.0) * C_RESERVOIR_GAL
                        * (3600.0 / C_LEAK_WINDOW_S);
    ELSE
        rLossRateGalHr := 0.0;
    END_IF;

    IF rDropPct < 0.0 THEN
        (* Level went UP - somebody added oil. Reset the evidence rather than
           carrying a stale suspicion across a top-up. *)
        iLeakCount := 0;
    ELSIF rLossRateGalHr > C_LEAK_RATE_GALHR AND rSuppress <= 0.0 THEN
        iLeakCount := iLeakCount + 1;
    ELSE
        iLeakCount := 0;
    END_IF;

    xMsgLeak     := iLeakCount >= C_LEAK_CONFIRMS;
    rRefLevel    := rComp;
    rWindowTimer := 0.0;
END_IF;
