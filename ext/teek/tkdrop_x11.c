/* tkdrop_x11.c - X11/XDND file drop target (stub)
 *
 * TODO: Implement X11 XDND protocol for file drop support.
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 */

#include <tcl.h>
#include <tk.h>
#include "tkdrop.h"

int
teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                          const char *widget_path)
{
    /* X11 XDND not yet implemented */
    Tcl_SetResult(interp, "file drop not yet supported on X11", TCL_STATIC);
    return TCL_ERROR;
}
