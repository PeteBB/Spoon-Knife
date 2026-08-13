(*
    FB_FunctionDispatch.st

    Scans the binding table and turns decoded button gestures into machine
    function requests.

    OUTPUT SEMANTICS. axFunction[] mirrors the gesture that produced it:
      - bound to GEST_HOLD   -> level, TRUE while the button is down
      - bound to any other   -> single-scan pulse
    Consumers must match. FUNC_CREEP_HOLD is read as a level; FUNC_RETURN_TO_DIG
    is read as a pulse. Getting this backwards produces a function that latches
    on and never releases, so the two kinds are kept visually distinct in the
    default table and the display editor enforces it.

    Multiple bindings may target the same function - they are OR'd, which is
    what lets a customer put "float" on two different buttons if they want it
    under either thumb.
*)
FUNCTION_BLOCK FB_FunctionDispatch
VAR_INPUT
    astButtons  : ARRAY[0..C_MAX_BUTTONS-1]  OF ST_ButtonState;
    astBindings : ARRAY[0..C_MAX_BINDINGS-1] OF ST_ButtonBinding;
    xEnable     : BOOL := TRUE;   (* FALSE suppresses all function requests   *)
END_VAR

VAR_OUTPUT
    axFunction   : ARRAY[0..21] OF BOOL;             (* indexed by E_MachineFunction *)
    (* Fed back into the FB_ButtonInput instances so that only buttons which
       actually carry a double-tap binding pay the 400 ms detection latency.
       Consumed one scan late, which is harmless - the table changes only when
       an operator edits it or an attachment is coupled. *)
    axNeedDouble : ARRAY[0..C_MAX_BUTTONS-1] OF BOOL;
END_VAR

VAR
    i     : INT;
    iBtn  : INT;
    iFunc : INT;
    xHit  : BOOL;
END_VAR

(* --- clear last scan ----------------------------------------------------- *)
FOR i := 0 TO 21 DO
    axFunction[i] := FALSE;
END_FOR;

FOR i := 0 TO C_MAX_BUTTONS - 1 DO
    axNeedDouble[i] := FALSE;
END_FOR;

(* --- scan the table ------------------------------------------------------ *)
FOR i := 0 TO C_MAX_BINDINGS - 1 DO

    IF astBindings[i].eFunction = FUNC_NONE THEN
        CONTINUE;
    END_IF;

    iBtn  := BYTE_TO_INT(astBindings[i].byButtonId);
    iFunc := astBindings[i].eFunction;

    (* Defensive: a corrupt NVM image or a bad attachment profile must not be
       able to index outside the arrays. *)
    IF iBtn < 0 OR iBtn >= C_MAX_BUTTONS OR iFunc < 0 OR iFunc > 21 THEN
        CONTINUE;
    END_IF;

    IF astBindings[i].eGesture = GEST_DOUBLE THEN
        axNeedDouble[iBtn] := TRUE;
    END_IF;

    IF NOT xEnable THEN
        CONTINUE;
    END_IF;

    CASE astBindings[i].eGesture OF
        GEST_SHORT:  xHit := astButtons[iBtn].xShort;
        GEST_LONG:   xHit := astButtons[iBtn].xLong;
        GEST_DOUBLE: xHit := astButtons[iBtn].xDouble;
        GEST_HOLD:   xHit := astButtons[iBtn].xHeld;
    ELSE
        xHit := FALSE;
    END_CASE;

    IF xHit THEN
        axFunction[iFunc] := TRUE;
    END_IF;

END_FOR;
