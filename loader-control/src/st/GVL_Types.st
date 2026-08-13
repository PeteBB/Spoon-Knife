(*
    GVL_Types.st
    Shared types, enumerations and tuning constants.

    All "command" values in this codebase are normalized REAL in the range
    -1.0 .. +1.0 unless a name explicitly says otherwise. Physical units
    (mA, rpm, bar, °C) appear only at the HAL boundary and in tuning constants.
    Sign convention: +1.0 = forward / raise / curl-back / extend.
*)

TYPE
    E_SpeedMode : (
        SPEED_CREEP   := 0,   (* precision work: propel scaled, engine free   *)
        SPEED_LOW     := 1,   (* "turtle" - 2-speed solenoid de-energized     *)
        SPEED_HIGH    := 2    (* "rabbit" - 2-speed solenoid energized        *)
    );

    E_InhibitCause : (
        INH_NONE            := 0,
        INH_NO_OPERATOR     := 1,   (* seat or seat bar                        *)
        INH_NOT_NEUTRAL     := 2,   (* joystick not centered at enable         *)
        INH_ENGINE_STOPPED  := 3,
        INH_JOYSTICK_FAULT  := 4,   (* channel plausibility failure            *)
        INH_OVERTEMP        := 5,
        INH_LOW_CHARGE      := 6,   (* hydrostat charge pressure below limit   *)
        INH_ESTOP           := 7,
        INH_CAN_TIMEOUT     := 8
    );

    (* Raw dual-channel axis as delivered by the HAL, already scaled to
       normalized units. Channel B is the inverse-slope redundant element of
       the Hall sensor: chA + chB should sum to a constant. *)
    ST_RawAxis : STRUCT
        rChA       : REAL;    (* -1.0 .. +1.0                                  *)
        rChB       : REAL;    (* -1.0 .. +1.0, inverse slope                   *)
        xInRange   : BOOL;    (* HAL asserts FALSE on open/short circuit       *)
    END_STRUCT;

    (* One operator's feel settings. Persisted to non-volatile memory and
       selected from the display. This struct is the product differentiator -
       keep it easy to extend. *)
    ST_OperatorProfile : STRUCT
        sName            : STRING(16);
        rPropelExpo      : REAL := 0.35;   (* 0 = linear .. 1 = full cubic     *)
        rSteerExpo       : REAL := 0.45;
        rAccelRate       : REAL := 1.4;    (* command units per second         *)
        rDecelRate       : REAL := 2.5;    (* faster than accel, deliberately  *)
        rMaxSpeedScale   : REAL := 1.0;    (* 0.1 .. 1.0 top-speed clamp       *)
        rSteerGainAtTop  : REAL := 0.45;   (* steering authority at full speed *)
        rLoaderExpo      : REAL := 0.25;
        rLoaderRate      : REAL := 2.0;
        rAuxExpo         : REAL := 0.20;
        rAuxRate         : REAL := 3.0;
    END_STRUCT;
END_TYPE


VAR_GLOBAL CONSTANT
    (* ---- Task timing ---------------------------------------------------- *)
    C_DT_FAST          : REAL := 0.010;   (* s, propel task period            *)
    C_DT_MED           : REAL := 0.050;   (* s, loader/aux task period        *)

    (* ---- Joystick plausibility ------------------------------------------ *)
    (* chA + chB nominally equals this sum; deviation beyond the tolerance
       for longer than the debounce time is a sensor fault, not noise. *)
    C_AXIS_SUM_NOMINAL : REAL := 0.0;
    C_AXIS_SUM_TOL     : REAL := 0.12;
    C_AXIS_FAULT_DEB_S : REAL := 0.060;   (* s                                *)

    C_AXIS_DEADBAND    : REAL := 0.07;    (* fraction of travel at center     *)
    C_NEUTRAL_WINDOW   : REAL := 0.10;    (* must be inside this to enable    *)

    (* ---- Proportional coil characteristic -------------------------------
       Placeholders. These MUST be replaced with measured values per valve
       and per pump. I_THRESHOLD is the current at which the spool/swashplate
       just begins to move; commanding below it produces heat and no motion,
       which is exactly the mushy deadband that makes a machine feel cheap. *)
    C_PUMP_I_THRESHOLD : REAL := 0.400;   (* A                                *)
    C_PUMP_I_MAX       : REAL := 1.100;   (* A                                *)
    C_VALVE_I_THRESHOLD: REAL := 0.350;   (* A                                *)
    C_VALVE_I_MAX       : REAL := 0.900;  (* A                                *)
    C_DITHER_HZ        : REAL := 110.0;   (* Hz, reduces spool stiction       *)

    (* ---- Anti-stall ------------------------------------------------------ *)
    C_STALL_DROOP_START: REAL := 120.0;   (* rpm below target: begin derate   *)
    C_STALL_DROOP_FULL : REAL := 380.0;   (* rpm below target: full derate    *)
    C_STALL_DERATE_MIN : REAL := 0.15;    (* never cut propel below this      *)
    C_STALL_KP         : REAL := 0.0035;  (* per rpm                          *)
    C_STALL_KI         : REAL := 0.0090;  (* per rpm per second               *)
    C_STALL_RECOVER_S  : REAL := 0.8;     (* s to blend derate back out       *)

    (* ---- Protection limits ---------------------------------------------- *)
    C_OIL_TEMP_DERATE_C: REAL := 95.0;
    C_OIL_TEMP_STOP_C  : REAL := 105.0;
    C_CHARGE_MIN_BAR   : REAL := 12.0;
    C_CAN_TIMEOUT_S    : REAL := 0.5;
END_VAR
