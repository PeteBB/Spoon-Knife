/*
 * laser_grade.c
 *
 * Laser grade control for an attachment with its own height cylinder.
 *
 * The machine drives forward and knows nothing. A rotating laser on a tripod
 * defines the design surface, a receiver on a mast measures height against it,
 * and this loop drives the attachment's own cylinder to stay on that plane.
 *
 * MCU-agnostic. Hardware sits behind the lg_hal_* functions, same split as
 * safety_core.c.
 *
 * ---------------------------------------------------------------------------
 * WHY PULSE-AND-SETTLE RATHER THAN A CONTINUOUS LOOP
 *
 * The obvious design - sample the error, drive the valve proportionally,
 * repeat fast - oscillates badly. Three lags sit in series:
 *
 *     valve and hydraulic response  ->  spool shift, flow, cylinder movement
 *     mechanical settling           ->  the attachment resettling on its skids
 *     measurement lag               ->  the receiver reading stabilising
 *
 * By the time a reading reflects your correction you have already applied three
 * more. The blade hunts and the finish is worse than manual.
 *
 * So: fire ONE pulse sized to the error, then WAIT long enough for the machine
 * to actually respond, then measure again. Slower on paper, far better finish,
 * and it never fights its own last correction.
 *
 * Pulse WIDTH carries the proportionality, which is what gives smooth
 * behaviour out of plain on/off solenoids - the only kind this module has.
 * ---------------------------------------------------------------------------
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/* ======================================================================== */
/* Tuning - all field-adjustable candidates                                  */
/* ======================================================================== */

/* Deadband. THE control the operator actually reaches for: tight for finish,
 * wide for rough cut. Put it on the pendant, not in a menu. */
#define LG_DEADBAND_MIN_MM      3
#define LG_DEADBAND_MAX_MM      50
#define LG_DEADBAND_DEFAULT_MM  8

/* Pulse sizing */
#define LG_PULSE_MIN_MS         60u     /* shortest useful nudge            */
#define LG_PULSE_MAX_MS         600u    /* longest single correction        */
#define LG_MS_PER_MM            18u     /* pulse growth per mm of error     */
#define LG_CONTINUOUS_MM        120     /* beyond this, drive continuously  */

/* Settle time after a pulse. Too short and it oscillates; too long and it
 * cannot keep up with ground speed. Scale with pulse length. */
#define LG_SETTLE_BASE_MS       250u
#define LG_SETTLE_PER_PULSE_PCT 60u     /* plus 60% of the pulse duration   */

/* Signal handling */
#define LG_SIGNAL_STABLE_MS     400u    /* stable before resuming control   */
#define LG_SIGNAL_LOST_MS       150u    /* missing before declaring loss    */

/* Stuck / end-of-stroke detection */
#define LG_STUCK_CYCLES         5       /* corrections with no improvement  */
#define LG_STUCK_IMPROVE_MM     3       /* what counts as improvement       */

/* First acquisition sanity - do not lunge at a huge error */
#define LG_ACQUIRE_MAX_MM       200

/* Discrete receivers report only above/on/below; synthesise an error so the
 * same loop works, just with fixed-width pulses. */
#define LG_DISCRETE_ERR_MM      25

/* ======================================================================== */
/* Hardware abstraction                                                      */
/* ======================================================================== */

/* Drive the attachment's height cylinder. Both false = valve centred.
 * Never both true - the caller guarantees it, but the HAL should too. */
extern void lg_hal_set_cylinder(bool raise, bool lower);

/* Operator feedback: on-grade lamp, above/below indication, fault. */
extern void lg_hal_indicate(bool on_grade, bool above, bool below, bool fault);

/* ======================================================================== */
/* Types                                                                     */
/* ======================================================================== */

typedef enum {
    LG_DISABLED = 0,
    LG_NO_SIGNAL,        /* enabled, waiting for a stable laser reading      */
    LG_ACQUIRE,          /* signal good but error too large to auto-correct  */
    LG_ON_GRADE,
    LG_PULSE,            /* correction pulse active                         */
    LG_SETTLE,           /* waiting for the machine to respond              */
    LG_YIELD,            /* operator is driving it manually                 */
    LG_FAULT_STUCK       /* correcting with no effect - end of stroke?      */
} lg_state_t;

typedef struct {
    bool    enabled;
    bool    manual_override;   /* operator is touching the height control    */

    bool    signal_valid;      /* receiver is seeing the laser plane         */
    bool    proportional;      /* receiver reports mm, not just high/low     */
    int32_t offset_mm;         /* + = ABOVE plane (blade too high)           */
    bool    above;             /* discrete receivers only                    */
    bool    below;

    int32_t deadband_mm;       /* operator setting                           */
} lg_input_t;

/* ======================================================================== */
/* State                                                                     */
/* ======================================================================== */

static struct {
    lg_state_t state;
    uint32_t   state_entered_ms;

    uint32_t   pulse_ms;          /* length of the pulse in progress        */
    bool       pulse_raise;

    uint32_t   signal_good_since_ms;
    uint32_t   signal_bad_since_ms;

    int32_t    err_at_pulse_start;
    uint8_t    no_improve_count;

    int32_t    filtered_mm;
    bool       filter_primed;
} g;

/* ======================================================================== */
/* Helpers                                                                   */
/* ======================================================================== */

static void lg_goto(lg_state_t s, uint32_t now_ms)
{
    g.state            = s;
    g.state_entered_ms = now_ms;
}

static uint32_t lg_elapsed(uint32_t now_ms)
{
    return (uint32_t)(now_ms - g.state_entered_ms);
}

/*
 * Turn the receiver reading into a single signed error in mm.
 * Positive means the blade is ABOVE grade and must come DOWN.
 */
static int32_t lg_raw_error(const lg_input_t *in)
{
    if (in->proportional) {
        return in->offset_mm;
    }
    /* Discrete receiver: fixed magnitude, direction only. Pulses end up a
     * fixed width, which is cruder but perfectly workable. */
    if (in->above) { return  LG_DISCRETE_ERR_MM; }
    if (in->below) { return -LG_DISCRETE_ERR_MM; }
    return 0;
}

/* Light IIR filter. The reading bounces as the machine pitches and the
 * attachment rides; smoothing here is cheaper than chasing noise with the
 * cylinder. */
static int32_t lg_filter(int32_t raw)
{
    if (!g.filter_primed) {
        g.filtered_mm  = raw;
        g.filter_primed = true;
    } else {
        g.filtered_mm += (raw - g.filtered_mm) / 3;
    }
    return g.filtered_mm;
}

static uint32_t lg_pulse_len_ms(int32_t err, int32_t deadband)
{
    int32_t excess = (err < 0 ? -err : err) - deadband;
    uint32_t ms;

    if (excess <= 0) {
        return 0u;
    }

    ms = LG_PULSE_MIN_MS + (uint32_t)excess * LG_MS_PER_MM;
    if (ms > LG_PULSE_MAX_MS) {
        ms = LG_PULSE_MAX_MS;
    }
    return ms;
}

static void lg_stop_cylinder(void)
{
    lg_hal_set_cylinder(false, false);
}

/* ======================================================================== */
/* Public API                                                                */
/* ======================================================================== */

void lg_init(void)
{
    memset(&g, 0, sizeof(g));
    g.state = LG_DISABLED;
    lg_stop_cylinder();
}

/*
 * Call at 20-50 Hz. Faster buys nothing - the mechanism is the slow part.
 */
void lg_tick(const lg_input_t *in, uint32_t now_ms)
{
    int32_t  err;
    int32_t  deadband;
    uint32_t settle_ms;
    bool     on_grade;

    /* --- Disabled: hands off, always ---------------------------------- */
    if (in == NULL || !in->enabled) {
        lg_stop_cylinder();
        lg_goto(LG_DISABLED, now_ms);
        g.filter_primed = false;
        lg_hal_indicate(false, false, false, false);
        return;
    }

    /* --- Operator always wins ------------------------------------------ */
    /* Yields the instant they touch the control, and resumes only after they
     * let go AND the reading has settled again. Auto grade that fights the
     * operator's hand is auto grade that gets switched off permanently. */
    if (in->manual_override) {
        lg_stop_cylinder();
        lg_goto(LG_YIELD, now_ms);
        g.filter_primed  = false;
        g.no_improve_count = 0;
        lg_hal_indicate(false, false, false, false);
        return;
    }

    /* --- Signal supervision -------------------------------------------- */
    if (in->signal_valid) {
        g.signal_bad_since_ms = 0u;
        if (g.signal_good_since_ms == 0u) {
            g.signal_good_since_ms = now_ms;
        }
    } else {
        g.signal_good_since_ms = 0u;
        if (g.signal_bad_since_ms == 0u) {
            g.signal_bad_since_ms = now_ms;
        }
    }

    /* Beam lost: STOP. Never drive the cylinder blind - that is how a
     * finished pad gets gouged. Hold what we have and say so. */
    if (!in->signal_valid &&
        (uint32_t)(now_ms - g.signal_bad_since_ms) >= LG_SIGNAL_LOST_MS) {
        lg_stop_cylinder();
        if (g.state != LG_NO_SIGNAL) {
            lg_goto(LG_NO_SIGNAL, now_ms);
        }
        g.filter_primed    = false;
        g.no_improve_count = 0;
        lg_hal_indicate(false, false, false, true);
        return;
    }

    /* Require a stable spell before trusting it again, so a flicker through a
     * branch does not produce a jerk of the blade. */
    if (g.signal_good_since_ms == 0u ||
        (uint32_t)(now_ms - g.signal_good_since_ms) < LG_SIGNAL_STABLE_MS) {
        if (g.state == LG_NO_SIGNAL || g.state == LG_YIELD ||
            g.state == LG_DISABLED) {
            lg_stop_cylinder();
            lg_hal_indicate(false, false, false, false);
            return;
        }
    }

    /* --- Error --------------------------------------------------------- */
    err = lg_filter(lg_raw_error(in));

    deadband = in->deadband_mm;
    if (deadband < LG_DEADBAND_MIN_MM) { deadband = LG_DEADBAND_MIN_MM; }
    if (deadband > LG_DEADBAND_MAX_MM) { deadband = LG_DEADBAND_MAX_MM; }

    on_grade = (labs((long)err) <= deadband);

    /* --- Fault latch --------------------------------------------------- */
    /* Cleared only by the operator disabling or taking manual control, both
     * handled above. */
    if (g.state == LG_FAULT_STUCK) {
        lg_stop_cylinder();
        lg_hal_indicate(false, err > 0, err < 0, true);
        return;
    }

    /* --- State machine -------------------------------------------------- */
    switch (g.state) {

    case LG_DISABLED:
    case LG_NO_SIGNAL:
    case LG_YIELD:
        /* Re-entering control. Do not lunge at a large error - make the
         * operator get roughly on grade first. */
        if (labs((long)err) > LG_ACQUIRE_MAX_MM) {
            lg_goto(LG_ACQUIRE, now_ms);
        } else {
            lg_goto(LG_ON_GRADE, now_ms);
        }
        lg_stop_cylinder();
        break;

    case LG_ACQUIRE:
        lg_stop_cylinder();
        if (labs((long)err) <= LG_ACQUIRE_MAX_MM) {
            lg_goto(LG_ON_GRADE, now_ms);
        }
        break;

    case LG_ON_GRADE:
        lg_stop_cylinder();
        if (!on_grade) {
            g.pulse_ms = lg_pulse_len_ms(err, deadband);
            if (g.pulse_ms > 0u) {
                /* err > 0 means above grade, so bring it DOWN. */
                g.pulse_raise         = (err < 0);
                g.err_at_pulse_start  = err;
                lg_goto(LG_PULSE, now_ms);
            }
        } else {
            g.no_improve_count = 0;
        }
        break;

    case LG_PULSE:
        lg_hal_set_cylinder(g.pulse_raise, !g.pulse_raise);

        /* A very large error drives continuously until it comes back into
         * range, rather than pulsing its way there one nudge at a time. */
        if (labs((long)err) > LG_CONTINUOUS_MM) {
            /* stay driving, but re-evaluate direction each tick */
            g.pulse_raise = (err < 0);
            break;
        }

        if (lg_elapsed(now_ms) >= g.pulse_ms) {
            lg_stop_cylinder();
            lg_goto(LG_SETTLE, now_ms);
        }
        break;

    case LG_SETTLE:
        lg_stop_cylinder();

        settle_ms = LG_SETTLE_BASE_MS
                  + (g.pulse_ms * LG_SETTLE_PER_PULSE_PCT) / 100u;

        if (lg_elapsed(now_ms) >= settle_ms) {
            /* Did that pulse actually achieve anything? If we keep asking and
             * nothing improves, the cylinder is at end of stroke, the blade is
             * buried, a coil has failed, or the valve is stuck. Free
             * diagnostics from logic we needed anyway. */
            long before = labs((long)g.err_at_pulse_start);
            long after  = labs((long)err);

            if ((before - after) < LG_STUCK_IMPROVE_MM) {
                g.no_improve_count++;
                if (g.no_improve_count >= LG_STUCK_CYCLES) {
                    lg_goto(LG_FAULT_STUCK, now_ms);
                    break;
                }
            } else {
                g.no_improve_count = 0;
            }

            lg_goto(LG_ON_GRADE, now_ms);
        }
        break;

    default:
        lg_stop_cylinder();
        lg_goto(LG_ON_GRADE, now_ms);
        break;
    }

    lg_hal_indicate(on_grade && g.state == LG_ON_GRADE,
                    err > deadband,
                    err < -deadband,
                    false);
}

/* Diagnostics for the pendant display. */
lg_state_t lg_get_state(void)      { return g.state; }
int32_t    lg_get_error_mm(void)   { return g.filtered_mm; }
