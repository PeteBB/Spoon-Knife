/*
 * grip_clamp.scad
 *
 * Parametric joystick-grip clamp for the transmitter pod.
 *
 * ---------------------------------------------------------------------------
 * WHY PARAMETRIC RATHER THAN A MODEL OF ONE GRIP
 *
 * A shell modelled precisely to one manufacturer's handle fits exactly one
 * manufacturer's handle. You do not control which machines your customers own,
 * rubber boots vary between model years, and they swell and wear.
 *
 * So this is a COMPLIANT clamp with a parametric bore, not a moulded negative.
 * One printed part covers a range of grip diameters, and the elastomer liner
 * absorbs the rest. To support a new machine you change one number and
 * reprint - you do not need CAD of the grip at all.
 *
 * ---------------------------------------------------------------------------
 * HOW TO USE IT
 *
 *   1. Measure the grip where you want the pod to sit. A $10 contour gauge
 *      gives you the cross-section directly; calipers give you the diameter.
 *   2. Set grip_dia below. Add liner_thk for the rubber you will line it with.
 *   3. Print, fit, adjust ONE number, reprint. Twenty-minute loop.
 *
 * The C opening springs over the grip and a strap or hose clamp through the
 * side slots takes the real load. The plastic locates; the strap holds.
 * ---------------------------------------------------------------------------
 */

/* ======================= PARAMETERS - EDIT THESE ======================== */

grip_dia      = 38;    // measured grip diameter at the mounting point, mm
liner_thk     = 2.0;   // elastomer / foam liner thickness, mm
wall          = 4.0;   // shell wall thickness, mm
clamp_len     = 55;    // length along the grip, mm
opening_deg   = 110;   // C opening angle - bigger springs on easier, holds less

pod_w         = 46;    // button pod footprint width, mm
pod_l         = 52;    // button pod footprint length, mm
pod_tilt      = 18;    // pod tilt toward the thumb, degrees

strap_w       = 13;    // strap or hose-clamp width, mm
strap_thk     = 2.0;   // slot height, mm

button_dia    = 12;    // panel-mount button hole, mm
button_rows   = 2;
button_cols   = 2;
button_pitch  = 20;    // centre-to-centre, mm

$fn           = 96;

/* ============================ DERIVED =================================== */

bore_r  = grip_dia/2 + liner_thk;
outer_r = bore_r + wall;

/* ============================ MODULES =================================== */

module c_clamp() {
    difference() {
        // shell
        cylinder(h = clamp_len, r = outer_r, center = true);

        // bore for grip + liner
        cylinder(h = clamp_len + 2, r = bore_r, center = true);

        // C opening, facing away from the pod
        rotate([0, 0, 180 - opening_deg/2])
            pie_cut(opening_deg, outer_r + 5, clamp_len + 2);

        // strap slots, two of them, clear of the opening
        for (z = [-clamp_len/4, clamp_len/4])
            translate([0, 0, z])
                strap_slot();
    }
}

// Wedge used to cut the C opening
module pie_cut(angle, r, h) {
    linear_extrude(height = h, center = true)
        polygon(points = concat(
            [[0,0]],
            [for (a = [0 : 5 : angle]) [r*cos(a), r*sin(a)]]
        ));
}

// A slot through the wall for a strap or hose clamp to pass under
module strap_slot() {
    difference() {
        cylinder(h = strap_w, r = outer_r + 1, center = true);
        cylinder(h = strap_w + 2, r = outer_r - strap_thk, center = true);
    }
}

module button_pod() {
    difference() {
        // pod body, tilted toward the thumb
        translate([0, outer_r + pod_l/2 - 6, 0])
            rotate([pod_tilt, 0, 0])
                minkowski() {
                    cube([pod_w - 6, pod_l - 6, 12], center = true);
                    sphere(r = 3);
                }

        // button holes
        translate([0, outer_r + pod_l/2 - 6, 0])
            rotate([pod_tilt, 0, 0])
                for (r = [0 : button_rows - 1])
                    for (c = [0 : button_cols - 1])
                        translate([
                            (c - (button_cols-1)/2) * button_pitch,
                            (r - (button_rows-1)/2) * button_pitch,
                            0
                        ])
                            cylinder(h = 40, r = button_dia/2, center = true);
    }
}

/* ============================ ASSEMBLY ================================== */

/*
 * Print orientation note: stand it on end (along the grip axis) so the C
 * opening springs across layer lines rather than along them. Printed flat,
 * the C will snap at the opening the first cold morning.
 */

union() {
    c_clamp();
    button_pod();
}
