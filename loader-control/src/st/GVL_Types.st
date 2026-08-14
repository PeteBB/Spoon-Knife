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
        (* 1.0 = skid (preserve turn radius) .. 0.0 = crawler (preserve
           forward speed). See FB_DriveMixer. Default leans slightly toward
           crawler because the load-based auto-bias only ever pushes further
           that way - starting at pure skid would make the bias one-sided. *)
        rSteerPriority   : REAL := 0.85;
        rRimpullSetting  : REAL := 1.0;    (* tractive effort ceiling, 0.3..1  *)
        rLoaderExpo      : REAL := 0.25;
        rLoaderRate      : REAL := 2.0;
        rAuxExpo         : REAL := 0.20;
        rAuxRate         : REAL := 3.0;
    END_STRUCT;

    E_PtoMode : (
        PTO_540   := 0,   (* 540 rpm at rated engine speed                   *)
        PTO_540E  := 1,   (* 540 rpm at reduced engine speed - economy       *)
        PTO_1000  := 2
    );

    E_PtoState : (
        PTO_OFF       := 0,
        PTO_FILL      := 1,   (* taking up clutch clearance, no torque yet   *)
        PTO_MODULATE  := 2,   (* ramping torque, droop-aware                 *)
        PTO_LOCKED    := 3,
        PTO_FAULT     := 4
    );

    E_PtoInhibit : (
        PTOINH_NONE          := 0,
        PTOINH_NO_OPERATOR   := 1,
        PTOINH_ENGINE_OFF    := 2,
        PTOINH_NEEDS_REQUEST := 3,   (* must re-request - never auto-resume  *)
        PTOINH_OVERLOAD      := 4,
        PTOINH_CLUTCH_SLIP   := 5,
        PTOINH_AUTO_RAISED   := 6    (* auto-PTO, hitch above threshold      *)
    );

    E_HeadlandState : (
        HL_WORKING   := 0,
        HL_RAISING   := 1,   (* lifting out of work                          *)
        HL_HEADLAND  := 2,   (* up, PTO stopped, waiting for the turn         *)
        HL_SPOOLING  := 3,   (* PTO back up to speed BEFORE entering ground   *)
        HL_LOWERING  := 4
    );

    (* Rear implement, from the ISOBUS node or selected on the display for
       dumb implements. Ramp time is the important field: a rotary cutter has
       enormous rotational inertia and slamming the clutch into it shocks the
       whole driveline. *)
    ST_ImplementProfile : STRUCT
        sName           : STRING(20);
        rPtoRampS       : REAL := 2.0;    (* clutch modulation time, s       *)
        rWorkingDepth   : REAL := 0.30;   (* hitch position 0..1             *)
        rDraftBlend     : REAL := 0.0;    (* 0 = position, 1 = full draft    *)
        rDropRate       : REAL := 0.5;    (* lowering speed limit, 0..1      *)
        xUsesPto        : BOOL := FALSE;
        xAutoPto        : BOOL := TRUE;   (* stop PTO when hitch raised      *)
        xIsRecognised   : BOOL := FALSE;
    END_STRUCT;

    (* Loaded automatically when an attachment is coupled, from the ID node on
       the attachment CAN bus. Falls back to a conservative default profile for
       dumb attachments and for anything the controller does not recognise. *)
    ST_AttachmentProfile : STRUCT
        sName            : STRING(20);
        wId              : WORD;
        rMaxFlowScale    : REAL := 1.0;    (* clamp on aux command, 0..1      *)
        rAuxRampUp       : REAL := 2.0;    (* command units/s                 *)
        rAuxRampDown     : REAL := 4.0;
        xAllowDetent     : BOOL := TRUE;   (* FALSE for anything with teeth   *)
        xAllowHighFlow   : BOOL := FALSE;
        xAllowReverse    : BOOL := TRUE;   (* FALSE for one-way motors        *)
        rMaxPressureBar  : REAL := 210.0;  (* aux circuit protection limit    *)
        rSoftStartS      : REAL := 0.5;    (* ramp when leaving neutral       *)
        xIsRecognised    : BOOL := FALSE;  (* FALSE = dumb/unknown attachment *)

        (* --- dozer blade with a frame push link, see doc 08 --------------- *)
        xIsDozer         : BOOL := FALSE;
        (* Boom angle at which the push-link pin runs out of its slot. Below
           this, thrust goes into the frame; above it, into the loader arms.
           THE defining number for FB_DozerMode - comes from the slot geometry. *)
        rSlotTopDeg      : REAL := 22.0;
        rSlotFadeDeg     : REAL := 6.0;    (* hand-over band below slot top   *)
        (* Rimpull ceiling once thrust is going through the arms. *)
        rArmsRimpullMax  : REAL := 0.35;
    END_STRUCT;

    E_FanState : (
        FAN_NORMAL     := 0,   (* forward, speed on demand                    *)
        FAN_SPINDOWN_F := 1,   (* slowing to stop before reversing            *)
        FAN_DWELL_A    := 2,   (* stopped - never reverse a spinning fan      *)
        FAN_REVERSE    := 3,   (* purging the cooler pack                     *)
        FAN_SPINDOWN_R := 4,
        FAN_DWELL_B    := 5
    );

    E_PushRegime : (
        PUSH_NONE        := 0,   (* no dozer fitted                          *)
        PUSH_FRAME       := 1,   (* pin in the slot - the strong path        *)
        PUSH_TRANSITION  := 2,   (* handing over                             *)
        PUSH_ARMS        := 3,   (* pin disengaged - the weak path           *)
        PUSH_CONSERVATIVE:= 4    (* something is untrusted - assume the worst *)
    );
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
