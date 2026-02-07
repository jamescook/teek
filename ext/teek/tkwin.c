/* tkwin.c - Tk window query functions
 *
 * Interp methods that require a live Tk display: idle detection,
 * coordinate queries, hit testing.
 */

#include "tcltkbridge.h"

/* ---------------------------------------------------------
 * Interp#user_inactive_time
 *
 * Get milliseconds since last user activity using Tk_GetUserInactiveTime.
 * Useful for implementing screensavers, idle timeouts, etc.
 *
 * Returns:
 *   Integer milliseconds of inactivity, or
 *   -1 if the display doesn't support inactivity queries
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/Inactive.html
 * --------------------------------------------------------- */

static VALUE
interp_user_inactive_time(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Display *display;
    long inactive_ms;

    /* Get the main window for display access */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Get the display */
    display = Tk_Display(mainWin);
    if (!display) {
        rb_raise(eTclError, "Could not get display");
    }

    /* Query user inactive time */
    inactive_ms = Tk_GetUserInactiveTime(display);

    return LONG2NUM(inactive_ms);
}

/* ---------------------------------------------------------
 * Interp#get_root_coords(window_path)
 *
 * Get absolute screen coordinates of a window's upper-left corner.
 *
 * Arguments:
 *   window_path - Tk window path (e.g., ".", ".frame.button")
 *
 * Returns [x, y] array of root window coordinates.
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/GetRootCrd.html
 * --------------------------------------------------------- */

static VALUE
interp_get_root_coords(VALUE self, VALUE window_path)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Window tkwin;
    int x, y;

    StringValue(window_path);

    /* Get the main window for hierarchy reference */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Find the target window by path */
    tkwin = Tk_NameToWindow(tip->interp, StringValueCStr(window_path), mainWin);
    if (!tkwin) {
        rb_raise(eTclError, "window not found: %s", StringValueCStr(window_path));
    }

    /* Get root coordinates */
    Tk_GetRootCoords(tkwin, &x, &y);

    return rb_ary_new_from_args(2, INT2NUM(x), INT2NUM(y));
}

/* ---------------------------------------------------------
 * Interp#coords_to_window(root_x, root_y)
 *
 * Find which window contains the given screen coordinates (hit testing).
 *
 * Arguments:
 *   root_x - X coordinate in root window (screen) coordinates
 *   root_y - Y coordinate in root window (screen) coordinates
 *
 * Returns window path string, or nil if no Tk window at that location.
 *
 * See: https://manpages.ubuntu.com/manpages/kinetic/man3/Tk_CoordsToWindow.3tk.html
 * --------------------------------------------------------- */

static VALUE
interp_coords_to_window(VALUE self, VALUE root_x, VALUE root_y)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Window foundWin;
    const char *pathName;

    /* Get the main window for application reference */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Find window at coordinates */
    foundWin = Tk_CoordsToWindow(NUM2INT(root_x), NUM2INT(root_y), mainWin);
    if (!foundWin) {
        return Qnil;
    }

    /* Get window path name */
    pathName = Tk_PathName(foundWin);
    if (!pathName) {
        return Qnil;
    }

    return rb_utf8_str_new_cstr(pathName);
}

/* ---------------------------------------------------------
 * Init_tkwin - Register Tk window query methods on Interp
 *
 * Called from Init_tcltklib in tcltkbridge.c.
 * --------------------------------------------------------- */

void
Init_tkwin(VALUE cInterp)
{
    rb_define_method(cInterp, "user_inactive_time", interp_user_inactive_time, 0);
    rb_define_method(cInterp, "get_root_coords", interp_get_root_coords, 1);
    rb_define_method(cInterp, "coords_to_window", interp_coords_to_window, 2);
}
