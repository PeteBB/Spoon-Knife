/*
 * safety_core.c
 *
 * Portable safety core for the wireless attachment control module.
 *
 * MCU-agnostic on purpose. Everything hardware-specific sits behind the
 * ac_hal_* functions declared below, so this file survives a change of
 * microcontroller, radio or driver topology - the same split used on the track
 * loader between src/st/ and src/hal/.
 *
 * ---------------------------------------------------------------------------
 * THE FOUR RULES THIS FILE EXISTS TO ENFORCE
 *
 *   1. Loss of link de-energises everything, within one watchdog period.
 *   2. Neutral-before-enable: after power-up or any link loss, the module
 *      accepts no command until it has seen a packet with every button
 *      released.
 *   3. Pairing is enforced. A packet for another module is discarded silently.
 *   4. (Mechanical, stated here because the code depends on it) THE VALVE MUST
 *      BE SPRING-CENTRED. Rules 1-3 all assume that removing current stops the
 *      function. On a detented valve they are worthless.
 *
 * Rule 2 is the one people leave out. Without it, a transmitter sitting in a
 * toolbox with a button held down actuates the attachment the instant the
 * battery goes in - with nobody near the controls.
 * ---------------------------------------------------------------------------
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

/* ======================================================================== */
/* Configuration                                                             */
/* ======================================================================== */

#define AC_MAX_CHANNELS        6

/* Link supervision. Transmitter sends at 20 Hz; we tolerate five misses. */
#define AC_HEARTBEAT_MS        50u
#define AC_LINK_TIMEOUT_MS     250u

/* Peak-and-hold. Full current to shift the spool, then PWM to hold it there.
 * Worth roughly 3x the runtime on a pack - see docs/00-module-design.md.
 *
 * VERIFY AGAINST THE ACTUAL COILS. Some cartridge valves need more hold
 * current to resist flow forces, and some suppliers do not permit PWM hold at
 * all. Ask before trusting these numbers. */
#define AC_PEAK_MS             120u
#define AC_PEAK_DUTY           255u        /* full on                        */
#define AC_HOLD_DUTY           90u         /* ~35% of 255                    */

/* Coil diagnostics */
#define AC_OPEN_COIL_MA        150         /* below this while driven = open */
#define AC_OVERCURRENT_MA      3000        /* above this = short             */
#define AC_FAULT_CONFIRM_MS    200u

/* ======================================================================== */
/* Hardware abstraction - implement these per target                         */
/* ======================================================================== */

/* Set PWM duty 0..255 on a solenoid channel. 0 must fully de-energise. */
extern void     ac_hal_set_duty(uint8_t channel, uint8_t duty);

/* Measured coil current in mA, or -1 if sensing is not fitted. */
extern int32_t  ac_hal_channel_current_ma(uint8_t channel);

/* Status indication. */
extern void     ac_hal_set_led(bool linked, bool armed, bool fault);

/* Persisted pairing ID. Returns 0 if unpaired. */
extern uint32_t ac_hal_load_pairing_id(void);
extern void     ac_hal_store_pairing_id(uint32_t id);

/* ======================================================================== */
/* Wire format                                                               */
/* ======================================================================== */

typedef struct {
    uint32_t pairing_id;
    uint16_t sequence;
    uint8_t  buttons;      /* bit N = channel N commanded on */
    uint8_t  crc;
} ac_packet_t;

/* ======================================================================== */
/* Internal state                                                            */
/* ======================================================================== */

typedef enum {
    AC_CH_OFF = 0,
    AC_CH_PEAK,            /* full current, shifting the spool */
    AC_CH_HOLD             /* PWM, holding it shifted          */
} ac_ch_state_t;

typedef struct {
    ac_ch_state_t state;
    uint32_t      entered_ms;
    uint32_t      fault_since_ms;
    bool          faulted;
} ac_channel_t;

static struct {
    uint32_t     pairing_id;
    uint32_t     last_packet_ms;
    uint16_t     last_sequence;
    bool         have_sequence;

    bool         linked;
    bool         armed;          /* rule 2 latch */
    uint8_t      commanded;      /* button bitmask currently honoured */

    ac_channel_t ch[AC_MAX_CHANNELS];
} g;

/* ======================================================================== */
/* Helpers                                                                   */
/* ======================================================================== */

static uint8_t ac_crc8(const ac_packet_t *p)
{
    /* CRC-8, polynomial 0x07. Covers everything except the crc field itself. */
    const uint8_t *d = (const uint8_t *)p;
    size_t n = sizeof(ac_packet_t) - 1u;
    uint8_t crc = 0xFFu;

    for (size_t i = 0; i < n; i++) {
        crc ^= d[i];
        for (uint8_t b = 0; b < 8u; b++) {
            crc = (crc & 0x80u) ? (uint8_t)((crc << 1) ^ 0x07u)
                                : (uint8_t)(crc << 1);
        }
    }
    return crc;
}

/* De-energise everything, right now. The one operation that must always work
 * and must never be conditional on anything. */
static void ac_all_off(void)
{
    for (uint8_t i = 0; i < AC_MAX_CHANNELS; i++) {
        ac_hal_set_duty(i, 0u);
        g.ch[i].state = AC_CH_OFF;
    }
    g.commanded = 0u;
}

/* ======================================================================== */
/* Public API                                                                */
/* ======================================================================== */

void ac_init(void)
{
    memset(&g, 0, sizeof(g));
    g.pairing_id = ac_hal_load_pairing_id();
    ac_all_off();
    /* Deliberately starts disarmed. Rule 2. */
}

void ac_enter_pairing(uint32_t new_id)
{
    ac_all_off();
    g.armed        = false;
    g.linked       = false;
    g.pairing_id   = new_id;
    g.have_sequence = false;
    ac_hal_store_pairing_id(new_id);
}

/*
 * Call on every received radio frame.
 * Returns true if the packet was accepted as valid and for us.
 */
bool ac_on_packet(const ac_packet_t *pkt, uint32_t now_ms)
{
    if (pkt == NULL) {
        return false;
    }

    /* Integrity before anything else - a corrupt packet must never reach the
     * command path. */
    if (ac_crc8(pkt) != pkt->crc) {
        return false;
    }

    /* Rule 3: not ours, not our business. Silent discard - no LED, no fault,
     * because on a site with three of these it is entirely normal traffic. */
    if (g.pairing_id == 0u || pkt->pairing_id != g.pairing_id) {
        return false;
    }

    /* Reject stale or replayed frames. Wrap-safe comparison. */
    if (g.have_sequence) {
        int16_t delta = (int16_t)(pkt->sequence - g.last_sequence);
        if (delta <= 0) {
            return false;
        }
    }
    g.last_sequence  = pkt->sequence;
    g.have_sequence  = true;

    g.last_packet_ms = now_ms;
    g.linked         = true;

    /* --- Rule 2: neutral-before-enable ---------------------------------- */
    if (!g.armed) {
        if (pkt->buttons == 0u) {
            /* Operator has released everything. Now we may accept commands. */
            g.armed = true;
        }
        /* Until then, nothing is honoured - not even this packet. */
        g.commanded = 0u;
        return true;
    }

    g.commanded = pkt->buttons;
    return true;
}

/*
 * Call at least every 10 ms. Drives the outputs and enforces the watchdog.
 *
 * Structured so that the link check happens FIRST and can only ever turn
 * things off. No path through this function can energise a channel while the
 * link is down or the module is disarmed.
 */
void ac_tick(uint32_t now_ms)
{
    bool any_fault = false;

    /* --- Rule 1: link watchdog ------------------------------------------ */
    if (g.linked && (uint32_t)(now_ms - g.last_packet_ms) > AC_LINK_TIMEOUT_MS) {
        g.linked = false;
        g.armed  = false;          /* re-arming requires neutral again */
        ac_all_off();
    }

    if (!g.linked || !g.armed) {
        ac_all_off();
        ac_hal_set_led(g.linked, g.armed, false);
        return;
    }

    /* --- Per-channel peak-and-hold -------------------------------------- */
    for (uint8_t i = 0; i < AC_MAX_CHANNELS; i++) {
        bool want = (g.commanded & (uint8_t)(1u << i)) != 0u;
        ac_channel_t *c = &g.ch[i];

        /* A latched channel fault stays latched until the operator releases
         * that button - otherwise a shorted coil retries forever. */
        if (c->faulted) {
            if (!want) {
                c->faulted        = false;
                c->fault_since_ms = 0u;
            }
            ac_hal_set_duty(i, 0u);
            c->state = AC_CH_OFF;
            any_fault = true;
            continue;
        }

        if (!want) {
            if (c->state != AC_CH_OFF) {
                ac_hal_set_duty(i, 0u);
                c->state = AC_CH_OFF;
            }
            c->fault_since_ms = 0u;
            continue;
        }

        switch (c->state) {
        case AC_CH_OFF:
            c->state      = AC_CH_PEAK;
            c->entered_ms = now_ms;
            ac_hal_set_duty(i, AC_PEAK_DUTY);
            break;

        case AC_CH_PEAK:
            if ((uint32_t)(now_ms - c->entered_ms) >= AC_PEAK_MS) {
                c->state      = AC_CH_HOLD;
                c->entered_ms = now_ms;
                ac_hal_set_duty(i, AC_HOLD_DUTY);
            }
            break;

        case AC_CH_HOLD:
            ac_hal_set_duty(i, AC_HOLD_DUTY);
            break;
        }

        /* --- Coil diagnostics ------------------------------------------- */
        /* Nearly free given current sense is fitted, and it turns "it doesn't
         * work" into "channel 3 coil is open" on the LED and in support. */
        int32_t ma = ac_hal_channel_current_ma(i);
        if (ma >= 0) {
            bool bad = (ma > AC_OVERCURRENT_MA) ||
                       (c->state == AC_CH_HOLD && ma < AC_OPEN_COIL_MA);

            if (bad) {
                if (c->fault_since_ms == 0u) {
                    c->fault_since_ms = now_ms;
                } else if ((uint32_t)(now_ms - c->fault_since_ms)
                           >= AC_FAULT_CONFIRM_MS) {
                    c->faulted = true;
                    ac_hal_set_duty(i, 0u);
                    c->state = AC_CH_OFF;
                }
            } else {
                c->fault_since_ms = 0u;
            }
        }
    }

    ac_hal_set_led(g.linked, g.armed, any_fault);
}

/* Diagnostics for a config app or a service screen. */
bool     ac_is_linked(void)  { return g.linked; }
bool     ac_is_armed(void)   { return g.armed;  }
uint8_t  ac_commanded(void)  { return g.commanded; }
