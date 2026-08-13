(*
    FB_ButtonInput.st

    Decodes one physical button into four gestures: short press, long press,
    double tap, and hold.

    LATENCY NOTE, and it matters. Double-tap detection is only possible by
    waiting out the double-tap window after a release to see whether a second
    press arrives. That means any button that can double-tap has its SHORT
    press delayed by C_BTN_DOUBLE_S - 400 ms of dead time between the operator
    pressing and the machine reacting.

    400 ms is fine on "return to dig". It is completely unacceptable on
    "horn", and it would be dangerous on anything safety-adjacent.

    So double-tap decoding is opt-in per button via xEnableDouble. When it is
    FALSE the short press fires on release with no added latency. The dispatch
    layer sets it automatically for any button that actually has a double-tap
    binding, so nobody has to remember.
*)
FUNCTION_BLOCK FB_ButtonInput
VAR_INPUT
    xRaw          : BOOL;          (* from the CAN grip message               *)
    xEnableDouble : BOOL := FALSE; (* see latency note above                  *)
    rDt           : REAL := 0.050;
END_VAR

VAR_OUTPUT
    stState : ST_ButtonState;
END_VAR

VAR
    xDebounced   : BOOL;
    xPrev        : BOOL;
    rDebTimer    : REAL;
    rHoldTimer   : REAL;
    rGapTimer    : REAL;
    xLongFired   : BOOL;
    xAwaitSecond : BOOL;
END_VAR

(* --- clear the single-scan pulses from last cycle ------------------------- *)
stState.xShort  := FALSE;
stState.xLong   := FALSE;
stState.xDouble := FALSE;

(* --- debounce ------------------------------------------------------------ *)
IF xRaw <> xDebounced THEN
    rDebTimer := rDebTimer + rDt;
    IF rDebTimer >= C_BTN_DEBOUNCE_S THEN
        xDebounced := xRaw;
        rDebTimer  := 0.0;
    END_IF;
ELSE
    rDebTimer := 0.0;
END_IF;

stState.xHeld := xDebounced;

(* --- press edge ---------------------------------------------------------- *)
IF xDebounced AND NOT xPrev THEN
    rHoldTimer := 0.0;
    xLongFired := FALSE;

    IF xAwaitSecond THEN
        (* second press inside the window - this is a double tap, and the
           first press is retroactively consumed as part of it *)
        stState.xDouble := TRUE;
        xAwaitSecond    := FALSE;
        rGapTimer       := 0.0;
    END_IF;
END_IF;

(* --- long press fires while still held, not on release ------------------- *)
(* Firing on release would make "teach" feel unresponsive: the operator holds,
   nothing happens, they let go, then it acts. Firing at the threshold lets the
   display flash "taught" while their thumb is still down, which is the
   feedback that makes the gesture discoverable. *)
IF xDebounced THEN
    rHoldTimer := rHoldTimer + rDt;
    IF rHoldTimer >= C_BTN_LONG_S AND NOT xLongFired THEN
        stState.xLong := TRUE;
        xLongFired    := TRUE;
        xAwaitSecond  := FALSE;   (* a long press cancels any pending double *)
    END_IF;
END_IF;

(* --- release edge -------------------------------------------------------- *)
IF NOT xDebounced AND xPrev THEN
    IF NOT xLongFired THEN
        IF xEnableDouble THEN
            (* defer: might be the first half of a double tap *)
            xAwaitSecond := TRUE;
            rGapTimer    := 0.0;
        ELSE
            stState.xShort := TRUE;
        END_IF;
    END_IF;
END_IF;

(* --- double-tap window expiry -------------------------------------------- *)
IF xAwaitSecond THEN
    rGapTimer := rGapTimer + rDt;
    IF rGapTimer >= C_BTN_DOUBLE_S THEN
        (* no second press arrived - it was a plain short press after all *)
        stState.xShort := TRUE;
        xAwaitSecond   := FALSE;
        rGapTimer      := 0.0;
    END_IF;
END_IF;

xPrev := xDebounced;
