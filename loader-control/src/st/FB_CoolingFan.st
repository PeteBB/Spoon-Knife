(*
    FB_CoolingFan.st

    Variable-speed, reversing hydraulic cooling fan.

    ---------------------------------------------------------------------------
    WHY THIS BLOCK EARNS ITS KEEP

    The reason air-cooled Deutz engines earned their reputation in agriculture
    is that there is no radiator core to plug. Chaff, dust, seed and leaf matter
    pack a cooler stack solid, the machine overheats, and somebody spends twenty
    minutes with an air hose every few hours.

    Air-cooling is no longer available above the small-engine emission
    thresholds (see docs/09-engine-selection.md), so this block is the modern
    answer to the same problem: run the fan backwards periodically and blow the
    pack clear. Combines and foragers have done it for years.

    The variable-speed half pays for itself separately:

      fuel    - a fixed fan runs at full power all day; this one usually does not
      noise   - the fan is typically the loudest thing on this class of machine
      warm-up - held at minimum until warm, which also gets the oil up to the
                temperature FB_AuxControl requires before allowing high flow

    ---------------------------------------------------------------------------
    TWO DETAILS THAT MATTER MORE THAN THE CONTROL LAW

    1. DWELL AT ZERO BETWEEN DIRECTION CHANGES. Reversing a spinning fan
       shock-loads the motor and its drive. The state machine spins down, waits
       for it to actually stop, and only then reverses. The dwell is not
       padding - it is the difference between a fan drive that lasts and one
       that does not.

    2. PURGING NEVER TAKES COOLING AWAY FROM A HOT MACHINE. Reversing is
       housekeeping. If any circuit is genuinely hot the cycle is deferred, not
       forced. A purge that trips a thermal derate has done more harm than the
       plugged core it was clearing.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_CoolingFan
VAR_INPUT
    rCoolantTempC   : REAL;
    rHydOilTempC    : REAL;
    rChargeAirTempC : REAL;

    xManualPurgeReq : BOOL;   (* pulse - operator asks for a purge now        *)
    xAutoPurgeOn    : BOOL := TRUE;

    xEngineRunning  : BOOL;
    xEnable         : BOOL;
    rDt             : REAL := 0.200;   (* slow task is fine for cooling       *)
END_VAR

VAR_OUTPUT
    rFanCmd         : REAL;   (* 0..1 magnitude to the fan valve              *)
    xFanReverse     : BOOL;   (* direction select                             *)
    eFanState       : E_FanState := FAN_NORMAL;

    rFanDemandPct   : REAL;   (* what the temperatures are asking for         *)
    xPurging        : BOOL;
    rMinsToPurge    : REAL;   (* display - countdown to the next auto purge   *)
    xPurgeDeferred  : BOOL;   (* wanted to purge but something is hot         *)
END_VAR

VAR CONSTANT
    (* --- demand curves: fan starts at ON, full by MAX --------------------- *)
    C_COOL_ON     : REAL := 85.0;    C_COOL_MAX    : REAL := 100.0;
    C_HYD_ON      : REAL := 70.0;    C_HYD_MAX     : REAL := 90.0;
    C_CHARGE_ON   : REAL := 50.0;    C_CHARGE_MAX  : REAL := 70.0;

    C_FAN_MIN     : REAL := 0.15;    (* always some flow while running        *)
    C_WARMUP_C    : REAL := 60.0;    (* below this, minimum fan               *)

    (* --- purge cycle ------------------------------------------------------ *)
    C_PURGE_INTERVAL_S : REAL := 1800.0;   (* 30 min of run time              *)
    C_PURGE_DURATION_S : REAL := 12.0;
    C_SPINDOWN_S       : REAL := 3.0;
    C_DWELL_S          : REAL := 1.5;
    C_PURGE_SPEED      : REAL := 0.85;

    (* --- purge inhibit: do not stop cooling a hot machine ----------------- *)
    C_INH_COOL_C   : REAL := 95.0;
    C_INH_HYD_C    : REAL := 85.0;
    C_INH_CHARGE_C : REAL := 65.0;
END_VAR

VAR
    rDemand      : REAL;
    rD           : REAL;
    rPurgeTimer  : REAL;
    rStateTimer  : REAL;
    xPurgeWanted : BOOL;
    xTooHot      : BOOL;
    xManualPrev  : BOOL;
    xManualLatch : BOOL;
END_VAR

(* =========================================================================
   0. Off
   ========================================================================= *)
IF NOT xEnable OR NOT xEngineRunning THEN
    rFanCmd       := 0.0;
    xFanReverse   := FALSE;
    eFanState     := FAN_NORMAL;
    xPurging      := FALSE;
    rStateTimer   := 0.0;
    xManualLatch  := FALSE;
    xPurgeDeferred:= FALSE;
    (* purge timer deliberately NOT reset - a machine restarted every ten
       minutes should still get a purge eventually *)
    RETURN;
END_IF;

(* =========================================================================
   1. Fan demand - highest bidder across the three circuits
   ========================================================================= *)
rDemand := 0.0;

rD := (rCoolantTempC - C_COOL_ON) / (C_COOL_MAX - C_COOL_ON);
IF rD > rDemand THEN rDemand := rD; END_IF;

rD := (rHydOilTempC - C_HYD_ON) / (C_HYD_MAX - C_HYD_ON);
IF rD > rDemand THEN rDemand := rD; END_IF;

rD := (rChargeAirTempC - C_CHARGE_ON) / (C_CHARGE_MAX - C_CHARGE_ON);
IF rD > rDemand THEN rDemand := rD; END_IF;

IF rDemand > 1.0 THEN rDemand := 1.0; END_IF;
IF rDemand < 0.0 THEN rDemand := 0.0; END_IF;

(* Warm-up: hold at minimum until the engine is up to temperature. Gets the
   hydraulic oil to the threshold FB_AuxControl needs before it will allow
   high flow, which is a real operator complaint on a cold morning. *)
IF rCoolantTempC < C_WARMUP_C THEN
    rDemand := 0.0;
END_IF;

IF rDemand < C_FAN_MIN THEN
    rDemand := C_FAN_MIN;
END_IF;

rFanDemandPct := 100.0 * rDemand;

(* =========================================================================
   2. Purge scheduling
   ========================================================================= *)
xTooHot := (rCoolantTempC   > C_INH_COOL_C)
        OR (rHydOilTempC    > C_INH_HYD_C)
        OR (rChargeAirTempC > C_INH_CHARGE_C);

IF xManualPurgeReq AND NOT xManualPrev THEN
    xManualLatch := TRUE;
END_IF;
xManualPrev := xManualPurgeReq;

rPurgeTimer  := rPurgeTimer + rDt;
rMinsToPurge := (C_PURGE_INTERVAL_S - rPurgeTimer) / 60.0;
IF rMinsToPurge < 0.0 THEN rMinsToPurge := 0.0; END_IF;

xPurgeWanted := xManualLatch
             OR (xAutoPurgeOn AND rPurgeTimer >= C_PURGE_INTERVAL_S);

(* Wanted but blocked - tell the operator rather than silently skipping, so a
   machine that never seems to purge has a visible reason. *)
xPurgeDeferred := xPurgeWanted AND xTooHot AND (eFanState = FAN_NORMAL);

(* =========================================================================
   3. Purge state machine
   ========================================================================= *)
CASE eFanState OF

    FAN_NORMAL:
        rFanCmd     := rDemand;
        xFanReverse := FALSE;
        xPurging    := FALSE;
        rStateTimer := 0.0;

        IF xPurgeWanted AND NOT xTooHot THEN
            eFanState := FAN_SPINDOWN_F;
        END_IF;

    FAN_SPINDOWN_F:
        (* Ramp to zero rather than dropping the command - the fan has real
           inertia and a hydraulic motor does not like being stalled. *)
        xPurging    := TRUE;
        xFanReverse := FALSE;
        rStateTimer := rStateTimer + rDt;
        rFanCmd     := rDemand * (1.0 - rStateTimer / C_SPINDOWN_S);
        IF rFanCmd < 0.0 THEN rFanCmd := 0.0; END_IF;

        IF rStateTimer >= C_SPINDOWN_S THEN
            eFanState   := FAN_DWELL_A;
            rStateTimer := 0.0;
        END_IF;

    FAN_DWELL_A:
        (* Stopped. Let it actually stop before reversing - see the header. *)
        rFanCmd     := 0.0;
        xFanReverse := FALSE;
        rStateTimer := rStateTimer + rDt;
        IF rStateTimer >= C_DWELL_S THEN
            eFanState   := FAN_REVERSE;
            rStateTimer := 0.0;
        END_IF;

    FAN_REVERSE:
        xFanReverse := TRUE;
        rFanCmd     := C_PURGE_SPEED;
        rStateTimer := rStateTimer + rDt;

        (* Abort early if the machine heats up mid-purge - cooling wins. *)
        IF rStateTimer >= C_PURGE_DURATION_S OR xTooHot THEN
            eFanState   := FAN_SPINDOWN_R;
            rStateTimer := 0.0;
        END_IF;

    FAN_SPINDOWN_R:
        xFanReverse := TRUE;
        rStateTimer := rStateTimer + rDt;
        rFanCmd     := C_PURGE_SPEED * (1.0 - rStateTimer / C_SPINDOWN_S);
        IF rFanCmd < 0.0 THEN rFanCmd := 0.0; END_IF;

        IF rStateTimer >= C_SPINDOWN_S THEN
            eFanState   := FAN_DWELL_B;
            rStateTimer := 0.0;
        END_IF;

    FAN_DWELL_B:
        rFanCmd     := 0.0;
        xFanReverse := FALSE;
        rStateTimer := rStateTimer + rDt;
        IF rStateTimer >= C_DWELL_S THEN
            eFanState    := FAN_NORMAL;
            rStateTimer  := 0.0;
            rPurgeTimer  := 0.0;
            xManualLatch := FALSE;
            xPurging     := FALSE;
        END_IF;

END_CASE;

IF rFanCmd > 1.0 THEN rFanCmd := 1.0; END_IF;
IF rFanCmd < 0.0 THEN rFanCmd := 0.0; END_IF;
