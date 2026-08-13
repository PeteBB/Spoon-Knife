(*
    FB_HeadlandSequence.st

    Two-press headland turn. One button, pressed at each end of the pass:

        press 1  ->  lift the implement out of work, then stop the PTO
        (turn)
        press 2  ->  bring the PTO back up to speed, THEN lower into work

    ---------------------------------------------------------------------------
    THE ORDERING IS THE WHOLE FEATURE

    Anyone can raise a hitch and stop a PTO. What makes this feel like a
    machine that knows what it is doing is doing the two things in the right
    order, in each direction:

      Leaving work  - the implement must be OUT OF THE GROUND before the PTO
                      stops, or the last thing it does is stall itself in the
                      dirt and shock-load the driveline on the way down.

      Entering work - the PTO must be AT SPEED before the implement touches
                      the ground. Dropping a stationary rotary cutter into
                      standing material is how driveline shear pins die, and
                      it is the single most common way an inexperienced
                      operator damages an implement.

    An operator doing this manually gets the ordering right when they are
    fresh and wrong when they are tired on the four hundredth pass. That is
    exactly the kind of thing to automate.
    ---------------------------------------------------------------------------
*)
FUNCTION_BLOCK FB_HeadlandSequence
VAR_INPUT
    xTrigger        : BOOL;   (* pulse - the headland button                  *)
    xSequenceOn     : BOOL := TRUE;  (* feature enabled                       *)

    rHitchPosition  : REAL;   (* 0..1 measured                                *)
    rPtoShaftRpm    : REAL;
    rPtoTargetRpm   : REAL;
    xImplementUsesPto : BOOL;

    xEnable         : BOOL;
    rDt             : REAL := 0.050;
END_VAR

VAR_OUTPUT
    xHitchRaise     : BOOL;   (* pulse to FB_HitchControl                     *)
    xHitchLower     : BOOL;   (* pulse to FB_HitchControl                     *)
    xPtoRequest     : BOOL;   (* level - gated into FB_PtoControl             *)
    eState          : E_HeadlandState := HL_WORKING;
    xSequencing     : BOOL;   (* display indicator                            *)
END_VAR

VAR CONSTANT
    C_RAISED_POS    : REAL := 0.80;   (* clear of the ground                  *)
    C_PTO_UP_PCT    : REAL := 0.90;   (* fraction of target rpm = "at speed"  *)
    C_SPOOL_TIMEOUT : REAL := 8.0;    (* s - do not wait forever              *)
    C_STEP_TIMEOUT  : REAL := 10.0;   (* s - abandon a stuck step             *)
END_VAR

VAR
    rTimer          : REAL;
END_VAR

xHitchRaise := FALSE;
xHitchLower := FALSE;

(* --- disabled or feature off: pass the PTO straight through --------------- *)
IF NOT xEnable OR NOT xSequenceOn THEN
    eState      := HL_WORKING;
    xPtoRequest := xEnable;
    xSequencing := FALSE;
    rTimer      := 0.0;
    RETURN;
END_IF;

xSequencing := (eState <> HL_WORKING);

CASE eState OF

    HL_WORKING:
        xPtoRequest := TRUE;
        rTimer      := 0.0;
        IF xTrigger THEN
            xHitchRaise := TRUE;      (* out of the ground first *)
            eState      := HL_RAISING;
        END_IF;

    HL_RAISING:
        (* PTO stays RUNNING until the implement is clear - see the header. *)
        xPtoRequest := TRUE;
        rTimer      := rTimer + rDt;

        IF rHitchPosition >= C_RAISED_POS OR rTimer > C_STEP_TIMEOUT THEN
            eState := HL_HEADLAND;
            rTimer := 0.0;
        END_IF;

        (* Pressing again mid-raise means "no, go back down". *)
        IF xTrigger THEN
            xHitchLower := TRUE;
            eState      := HL_WORKING;
        END_IF;

    HL_HEADLAND:
        xPtoRequest := FALSE;         (* now it is safe to stop *)
        IF xTrigger THEN
            eState := HL_SPOOLING;
            rTimer := 0.0;
        END_IF;

    HL_SPOOLING:
        (* PTO up to speed BEFORE the implement enters the ground. *)
        xPtoRequest := TRUE;
        rTimer      := rTimer + rDt;

        IF NOT xImplementUsesPto THEN
            xHitchLower := TRUE;
            eState      := HL_LOWERING;
            rTimer      := 0.0;

        ELSIF rPtoTargetRpm > 50.0
              AND rPtoShaftRpm >= C_PTO_UP_PCT * rPtoTargetRpm THEN
            xHitchLower := TRUE;
            eState      := HL_LOWERING;
            rTimer      := 0.0;

        ELSIF rTimer > C_SPOOL_TIMEOUT THEN
            (* PTO never came up - something is wrong. Do NOT lower into the
               ground; stay up and let the operator see the fault. Lowering a
               dead implement into standing material is the failure this
               whole block exists to prevent. *)
            eState := HL_HEADLAND;
            rTimer := 0.0;
        END_IF;

    HL_LOWERING:
        xPtoRequest := TRUE;
        rTimer      := rTimer + rDt;
        IF rHitchPosition <= C_RAISED_POS OR rTimer > C_STEP_TIMEOUT THEN
            eState := HL_WORKING;
            rTimer := 0.0;
        END_IF;

END_CASE;
