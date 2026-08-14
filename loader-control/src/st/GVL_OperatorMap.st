(*
    GVL_OperatorMap.st

    Types and defaults for the configurable button -> function binding.

    The whole point of this file is that NOTHING downstream of it knows which
    physical button drives which machine function. Buttons emit gestures; the
    binding table turns gestures into function requests. The table lives in
    non-volatile memory, is editable from the display, and can be overridden
    wholesale by an attachment profile.

    Adding a new machine function = add an enum member, add a default binding,
    consume the flag. No wiring change, no harness change.
*)

TYPE
    E_ButtonGesture : (
        GEST_SHORT  := 0,   (* pressed and released inside the short window   *)
        GEST_LONG   := 1,   (* held past the long threshold                   *)
        GEST_DOUBLE := 2,   (* two short presses inside the double window     *)
        GEST_HOLD   := 3    (* level, true for as long as it is held down     *)
    );

    (* Machine functions a button may be bound to.
       ORDER IS PART OF THE STORED CONFIGURATION - append new members at the
       end only, never insert, or every saved binding table in the field
       shifts by one and customers get surprises. *)
    E_MachineFunction : (
        FUNC_NONE              := 0,
        (* travel *)
        FUNC_TWO_SPEED_TOGGLE  := 1,
        FUNC_CREEP_HOLD        := 2,
        FUNC_CREEP_TOGGLE      := 3,
        (* engine and machine *)
        FUNC_HORN              := 4,
        FUNC_ENGINE_RPM_UP     := 5,
        FUNC_ENGINE_RPM_DOWN   := 6,
        FUNC_WORK_LIGHTS       := 7,
        FUNC_RIDE_CONTROL      := 8,
        (* auxiliary hydraulics *)
        FUNC_AUX_DETENT        := 9,
        FUNC_AUX2_TOGGLE       := 10,
        FUNC_HIGH_FLOW_TOGGLE  := 11,
        (* loader *)
        FUNC_RETURN_TO_DIG     := 12,
        FUNC_TEACH_DIG         := 13,
        FUNC_RETURN_TO_CARRY   := 14,
        FUNC_TEACH_CARRY       := 15,
        FUNC_FLOAT_TOGGLE      := 16,
        FUNC_SELF_LEVEL_TOGGLE := 17,
        FUNC_BUCKET_SHAKE      := 18,
        FUNC_TEACH_HEIGHT_LIM  := 19,
        FUNC_HEIGHT_LIM_TOGGLE := 20,
        (* operator profile *)
        FUNC_PROFILE_NEXT      := 21,
        FUNC_COUNT             := 22   (* keep last - array sizing            *)
    );

    (* Decoded state of one physical button, produced by FB_ButtonInput.
       The three gesture members are single-scan pulses; xHeld is a level. *)
    ST_ButtonState : STRUCT
        xShort  : BOOL;
        xLong   : BOOL;
        xDouble : BOOL;
        xHeld   : BOOL;
    END_STRUCT;

    ST_ButtonBinding : STRUCT
        byButtonId : BYTE;              (* index into the button array        *)
        eGesture   : E_ButtonGesture;
        eFunction  : E_MachineFunction;
        xLocked    : BOOL;              (* TRUE = display editor must refuse  *)
    END_STRUCT;
END_TYPE


VAR_GLOBAL CONSTANT
    C_MAX_BUTTONS  : INT := 16;
    C_MAX_BINDINGS : INT := 32;

    (* --- gesture timing --------------------------------------------------- *)
    C_BTN_DEBOUNCE_S : REAL := 0.020;
    C_BTN_LONG_S     : REAL := 0.800;
    C_BTN_DOUBLE_S   : REAL := 0.400;

    (* --- physical button ids ---------------------------------------------
       Index into the button array as assembled by the HAL from the two CAN
       joystick messages. Changing a grip supplier changes only this list and
       the HAL - no application code moves. *)
    BTN_L_THUMB_TOP   : BYTE := 0;
    BTN_L_THUMB_FRONT : BYTE := 1;
    BTN_L_TRIGGER     : BYTE := 2;
    BTN_L_ROCKER_UP   : BYTE := 3;
    BTN_L_ROCKER_DN   : BYTE := 4;
    BTN_L_TOGGLE      : BYTE := 5;

    BTN_R_THUMB_TOP   : BYTE := 8;
    BTN_R_THUMB_FRONT : BYTE := 9;
    BTN_R_TRIGGER     : BYTE := 10;
    BTN_R_BUTTON4     : BYTE := 11;
    BTN_R_TOGGLE      : BYTE := 12;
END_VAR


VAR_GLOBAL
    (* Default binding table. Loaded on first boot or on "restore defaults",
       then overwritten from NVM. Matches docs/02-operator-interface.md.

       Note how return-to-dig and return-to-carry each occupy one button using
       short-press-to-recall / long-press-to-teach. That pattern is what keeps
       a twenty-function machine on a ten-button pair of grips. *)
    g_astDefaultBindings : ARRAY[0..C_MAX_BINDINGS-1] OF ST_ButtonBinding := [
        (* --- left grip: travel and machine ------------------------------- *)
        (byButtonId := 0,  eGesture := GEST_SHORT,  eFunction := FUNC_TWO_SPEED_TOGGLE),
        (byButtonId := 1,  eGesture := GEST_HOLD,   eFunction := FUNC_HORN,  xLocked := TRUE),
        (byButtonId := 2,  eGesture := GEST_HOLD,   eFunction := FUNC_CREEP_HOLD),
        (byButtonId := 2,  eGesture := GEST_DOUBLE, eFunction := FUNC_CREEP_TOGGLE),
        (byButtonId := 3,  eGesture := GEST_HOLD,   eFunction := FUNC_ENGINE_RPM_UP),
        (byButtonId := 4,  eGesture := GEST_HOLD,   eFunction := FUNC_ENGINE_RPM_DOWN),
        (byButtonId := 5,  eGesture := GEST_SHORT,  eFunction := FUNC_WORK_LIGHTS),
        (byButtonId := 5,  eGesture := GEST_LONG,   eFunction := FUNC_PROFILE_NEXT),

        (* --- right grip: loader and attachment --------------------------- *)
        (byButtonId := 10, eGesture := GEST_SHORT,  eFunction := FUNC_AUX_DETENT),
        (byButtonId := 8,  eGesture := GEST_SHORT,  eFunction := FUNC_RETURN_TO_DIG),
        (byButtonId := 8,  eGesture := GEST_LONG,   eFunction := FUNC_TEACH_DIG),
        (byButtonId := 8,  eGesture := GEST_DOUBLE, eFunction := FUNC_BUCKET_SHAKE),
        (byButtonId := 9,  eGesture := GEST_SHORT,  eFunction := FUNC_FLOAT_TOGGLE),
        (byButtonId := 9,  eGesture := GEST_LONG,   eFunction := FUNC_TEACH_HEIGHT_LIM),
        (byButtonId := 11, eGesture := GEST_SHORT,  eFunction := FUNC_AUX2_TOGGLE),
        (byButtonId := 11, eGesture := GEST_LONG,   eFunction := FUNC_SELF_LEVEL_TOGGLE),
        (byButtonId := 12, eGesture := GEST_SHORT,  eFunction := FUNC_HIGH_FLOW_TOGGLE),
        (byButtonId := 12, eGesture := GEST_LONG,   eFunction := FUNC_RIDE_CONTROL)
        (* remaining entries default to FUNC_NONE and are free for the
           customer, or for an attachment profile to claim *)
    ];
END_VAR
