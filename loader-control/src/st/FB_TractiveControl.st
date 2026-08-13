(*
    FB_TractiveControl.st

    Rimpull limiting and slip control. The crossover concept's tier-1 feature.

    ---------------------------------------------------------------------------
    RIMPULL LIMITING - why refusing to push harder makes the machine dig better

    When a CTL drives into a pile, propel and work hydraulics compete for one
    engine. The tracks will happily convert every available horsepower into
    slip, and slip does three bad things at once: it fails to fill the bucket,
    it steals the power the bucket needed to curl, and it grinds the most
    expensive consumable on the machine into the dirt.

    So we put a ceiling on tractive effort - implemented as a limit on propel
    loop pressure, since pressure IS torque in a hydrostat - and the operator
    sets that ceiling. Below the ceiling the machine behaves normally. At the
    ceiling, propel displacement backs off, and the horsepower that would have
    become smoke stays available for lift and curl.

    Cat proved this on wheel loaders with rimpull control and the impeller
    clutch. Nobody has put it on a compact track loader, which is where it
    matters most: on rubber tracks, slip is not merely lost time, it is the
    machine's single largest running cost being actively destroyed.

    ---------------------------------------------------------------------------
    GROUND SPEED - an honest note

    Slip means track speed exceeding true ground speed, so we need to know
    ground speed, and this machine has no direct measurement of it.

    The estimator below fuses two imperfect sources: an IMU (good short-term
    dynamics, integrates drift without bound) and the SLOWER of the two track
    speeds (drift-free, but reads high when both tracks slip together). Each
    covers the other's failure. It is genuinely good enough to catch the
    one-track spin that accounts for most real slip events, and adequate for
    the symmetric case.

    It is NOT good enough for a payload-per-hour claim or a grade control
    interface. If those matter later, add GPS or a doppler radar ground speed
    sensor and demote this to the fallback. Do not let a spec sheet be written
    against this estimator.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_TractiveControl
VAR_INPUT
    rCmdLeft        : REAL;   (* -1..+1 from FB_DriveMixer                    *)
    rCmdRight       : REAL;

    rPressLeftBar   : REAL;   (* propel loop high-side pressure, per side     *)
    rPressRightBar  : REAL;

    rTrackSpeedL    : REAL;   (* kph, signed, from the Hall pickups           *)
    rTrackSpeedR    : REAL;

    rLongAccel      : REAL;   (* m/s^2, longitudinal, from the frame IMU      *)

    (* Operator-set tractive effort ceiling, 0.3 .. 1.0. Lower it on soft
       ground or when track life matters more than cycle time. *)
    rRimpullSetting : REAL := 1.0;

    xSlipControlOn  : BOOL := TRUE;
    xEnable         : BOOL;
    rDt             : REAL := 0.010;
END_VAR

VAR_OUTPUT
    rOutLeft        : REAL;
    rOutRight       : REAL;

    xRimpullActive  : BOOL;   (* at the effort ceiling - display indicator    *)
    xSlipLeft       : BOOL;
    xSlipRight      : BOOL;

    rEffortPct      : REAL;   (* 0..100, live tractive effort, for the display*)
    rGroundSpeedKph : REAL;   (* estimate, published for ride control etc.    *)

    (* Worst-case slip of the two tracks, 0..1. Consumed by FB_HitchControl
       for slip-referenced draft control - see
       docs/05-rear-implement-architecture.md section 7. *)
    rSlipRatioMax   : REAL;
END_VAR

VAR CONSTANT
    (* --- CALIBRATION VALUES - measure these on the machine --------------- *)
    C_PROPEL_MAX_BAR : REAL := 450.0;   (* hydrostat working pressure limit   *)
    C_RIMPULL_KP     : REAL := 0.0016;  (* per bar of overshoot               *)
    C_RIMPULL_KI     : REAL := 0.0040;  (* per bar per second                 *)
    C_RIMPULL_MIN    : REAL := 0.20;    (* never cut propel below this        *)
    C_RIMPULL_REC_S  : REAL := 0.6;     (* s to blend the limit back out      *)

    C_SLIP_RATIO     : REAL := 0.25;    (* 25% over ground speed = slipping   *)
    C_SLIP_DEB_S     : REAL := 0.25;    (* sustained before we act            *)
    C_SLIP_CUT       : REAL := 0.55;    (* how hard to derate a spinning side *)
    C_SLIP_REC_S     : REAL := 1.0;

    C_STOPPED_KPH    : REAL := 0.15;    (* below this, call it stationary     *)
    C_IMU_TRUST      : REAL := 0.90;    (* IMU vs track-speed fusion weight   *)
END_VAR

VAR
    rLimitBar    : REAL;
    rErrL        : REAL;
    rErrR        : REAL;
    rIntL        : REAL;
    rIntR        : REAL;
    rRimDerL     : REAL := 1.0;
    rRimDerR     : REAL := 1.0;
    rRed         : REAL;
    rRec         : REAL;

    rSpeedImu    : REAL;
    rSlowerTrack : REAL;
    rAbsL        : REAL;
    rAbsR        : REAL;

    rSlipRatioL  : REAL;
    rSlipRatioR  : REAL;
    rSlipTimerL  : REAL;
    rSlipTimerR  : REAL;
    rSlipDerL    : REAL := 1.0;
    rSlipDerR    : REAL := 1.0;

    rPeakPress   : REAL;
END_VAR

(* =========================================================================
   0. Bail out cleanly
   ========================================================================= *)
IF NOT xEnable THEN
    rOutLeft  := 0.0;
    rOutRight := 0.0;
    rIntL := 0.0;      rIntR := 0.0;
    rRimDerL := 1.0;   rRimDerR := 1.0;
    rSlipDerL := 1.0;  rSlipDerR := 1.0;
    rSlipTimerL := 0.0; rSlipTimerR := 0.0;
    rSpeedImu := 0.0;
    xRimpullActive := FALSE;
    xSlipLeft := FALSE;
    xSlipRight := FALSE;
    rEffortPct := 0.0;
    rGroundSpeedKph := 0.0;
    RETURN;
END_IF;

(* =========================================================================
   1. Ground speed estimate - see the note in the header
   ========================================================================= *)
rAbsL := ABS(rTrackSpeedL);
rAbsR := ABS(rTrackSpeedR);

IF rAbsL < rAbsR THEN
    rSlowerTrack := rAbsL;
ELSE
    rSlowerTrack := rAbsR;
END_IF;

(* IMU term: integrate longitudinal acceleration. 3.6 converts m/s to kph. *)
rSpeedImu := rSpeedImu + rLongAccel * rDt * 3.6;
IF rSpeedImu < 0.0 THEN rSpeedImu := 0.0; END_IF;

(* Fuse. The slower track bounds the IMU's drift; the IMU catches the case
   where both tracks slip together and the slower track lies. *)
rSpeedImu := C_IMU_TRUST * rSpeedImu + (1.0 - C_IMU_TRUST) * rSlowerTrack;

(* Hard reset when the machine is demonstrably stopped - this is what keeps
   integration drift from accumulating across a shift. *)
IF rAbsL < C_STOPPED_KPH AND rAbsR < C_STOPPED_KPH THEN
    rSpeedImu := 0.0;
END_IF;

rGroundSpeedKph := rSpeedImu;

(* =========================================================================
   2. Rimpull limiting - PI per side on propel loop pressure
   ========================================================================= *)
rLimitBar := rRimpullSetting * C_PROPEL_MAX_BAR;

(* --- left --- *)
rErrL := rPressLeftBar - rLimitBar;
IF rErrL > 0.0 THEN
    rIntL := rIntL + rErrL * rDt;
    IF rIntL * C_RIMPULL_KI > 1.0 THEN
        rIntL := 1.0 / C_RIMPULL_KI;          (* anti-windup *)
    END_IF;

    rRed := C_RIMPULL_KP * rErrL + C_RIMPULL_KI * rIntL;
    IF rRed > 1.0 THEN rRed := 1.0; END_IF;

    rRimDerL := 1.0 - rRed * (1.0 - C_RIMPULL_MIN);
    IF rRimDerL < C_RIMPULL_MIN THEN rRimDerL := C_RIMPULL_MIN; END_IF;
ELSE
    rIntL := 0.0;
    (* Blend back rather than stepping - a step release dumps displacement
       into the pump and the machine lunges out of the pile. *)
    rRec := rDt / C_RIMPULL_REC_S;
    rRimDerL := rRimDerL + rRec;
    IF rRimDerL > 1.0 THEN rRimDerL := 1.0; END_IF;
END_IF;

(* --- right --- *)
rErrR := rPressRightBar - rLimitBar;
IF rErrR > 0.0 THEN
    rIntR := rIntR + rErrR * rDt;
    IF rIntR * C_RIMPULL_KI > 1.0 THEN
        rIntR := 1.0 / C_RIMPULL_KI;
    END_IF;

    rRed := C_RIMPULL_KP * rErrR + C_RIMPULL_KI * rIntR;
    IF rRed > 1.0 THEN rRed := 1.0; END_IF;

    rRimDerR := 1.0 - rRed * (1.0 - C_RIMPULL_MIN);
    IF rRimDerR < C_RIMPULL_MIN THEN rRimDerR := C_RIMPULL_MIN; END_IF;
ELSE
    rIntR := 0.0;
    rRec := rDt / C_RIMPULL_REC_S;
    rRimDerR := rRimDerR + rRec;
    IF rRimDerR > 1.0 THEN rRimDerR := 1.0; END_IF;
END_IF;

xRimpullActive := (rRimDerL < 0.98) OR (rRimDerR < 0.98);

(* =========================================================================
   3. Slip control
   -------------------------------------------------------------------------
   Only meaningful once the machine is actually moving - at a standstill every
   ratio is noise, and a false slip trip on takeoff feels like a broken
   machine.
   ========================================================================= *)
IF xSlipControlOn AND rGroundSpeedKph > 0.5 THEN

    IF rAbsL > 0.1 THEN
        rSlipRatioL := (rAbsL - rGroundSpeedKph) / rAbsL;
    ELSE
        rSlipRatioL := 0.0;
    END_IF;

    IF rAbsR > 0.1 THEN
        rSlipRatioR := (rAbsR - rGroundSpeedKph) / rAbsR;
    ELSE
        rSlipRatioR := 0.0;
    END_IF;

    (* --- left --- *)
    IF rSlipRatioL > C_SLIP_RATIO THEN
        rSlipTimerL := rSlipTimerL + rDt;
    ELSE
        rSlipTimerL := 0.0;
    END_IF;

    IF rSlipTimerL > C_SLIP_DEB_S THEN
        xSlipLeft := TRUE;
        rSlipDerL := C_SLIP_CUT;
    ELSE
        xSlipLeft := FALSE;
        rSlipDerL := rSlipDerL + rDt / C_SLIP_REC_S;
        IF rSlipDerL > 1.0 THEN rSlipDerL := 1.0; END_IF;
    END_IF;

    (* --- right --- *)
    IF rSlipRatioR > C_SLIP_RATIO THEN
        rSlipTimerR := rSlipTimerR + rDt;
    ELSE
        rSlipTimerR := 0.0;
    END_IF;

    IF rSlipTimerR > C_SLIP_DEB_S THEN
        xSlipRight := TRUE;
        rSlipDerR := C_SLIP_CUT;
    ELSE
        xSlipRight := FALSE;
        rSlipDerR := rSlipDerR + rDt / C_SLIP_REC_S;
        IF rSlipDerR > 1.0 THEN rSlipDerR := 1.0; END_IF;
    END_IF;

ELSE
    xSlipLeft   := FALSE;
    xSlipRight  := FALSE;
    rSlipTimerL := 0.0;
    rSlipTimerR := 0.0;
    rSlipDerL   := 1.0;
    rSlipDerR   := 1.0;
    rSlipRatioL := 0.0;
    rSlipRatioR := 0.0;
END_IF;

(* Publish the worse of the two for the hitch's draft loop. *)
IF rSlipRatioL > rSlipRatioR THEN
    rSlipRatioMax := rSlipRatioL;
ELSE
    rSlipRatioMax := rSlipRatioR;
END_IF;
IF rSlipRatioMax < 0.0 THEN rSlipRatioMax := 0.0; END_IF;

(* =========================================================================
   4. Apply, and publish effort for the display
   ========================================================================= *)
rOutLeft  := rCmdLeft  * rRimDerL * rSlipDerL;
rOutRight := rCmdRight * rRimDerR * rSlipDerR;

IF rPressLeftBar > rPressRightBar THEN
    rPeakPress := rPressLeftBar;
ELSE
    rPeakPress := rPressRightBar;
END_IF;

rEffortPct := 100.0 * rPeakPress / C_PROPEL_MAX_BAR;
IF rEffortPct > 100.0 THEN rEffortPct := 100.0; END_IF;
IF rEffortPct < 0.0   THEN rEffortPct := 0.0;   END_IF;
