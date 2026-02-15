/* tkdrop.c - File drop target support (common entry point)
 *
 * Provides Interp#register_drop_target(window_path) which delegates
 * to platform-specific teek_register_drop_target().
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 */

#include "tcltkbridge.h"
#include "tkdrop.h"

/* ---------------------------------------------------------
 * Interp#register_drop_target(window_path)
 *
 * Register a Tk widget as a native file drop target.
 * After registration, dropping a file onto the widget generates
 * a <<DropFile>> virtual event with the file path in -data.
 *
 * Arguments:
 *   window_path - Tk widget path (e.g., ".", ".frame")
 *
 * Returns: nil
 * --------------------------------------------------------- */

static VALUE
interp_register_drop_target(VALUE self, VALUE window_path)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Window tkwin;
    int result;

    StringValue(window_path);

    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    tkwin = Tk_NameToWindow(tip->interp, StringValueCStr(window_path), mainWin);
    if (!tkwin) {
        rb_raise(eTclError, "window not found: %s", StringValueCStr(window_path));
    }

    Tk_MakeWindowExist(tkwin);

    result = teek_register_drop_target(tip->interp, tkwin, StringValueCStr(window_path));
    if (result != TCL_OK) {
        rb_raise(eTclError, "failed to register drop target: %s",
                 Tcl_GetStringResult(tip->interp));
    }

    return Qnil;
}

/* ---------------------------------------------------------
 * Init_tkdrop - Register drop target methods on Interp
 *
 * Called from Init_tcltklib in tcltkbridge.c.
 * --------------------------------------------------------- */

void
Init_tkdrop(VALUE cInterp)
{
    rb_define_method(cInterp, "register_drop_target", interp_register_drop_target, 1);
}
