/* tkdrop.h - Native file drop target support
 *
 * Cross-platform abstraction for registering Tk widgets as file drop targets.
 * Each platform implements teek_register_drop_target() which hooks into the
 * OS drag-and-drop system and generates <<DropFile>> virtual events.
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 * See THIRD_PARTY_NOTICES for attribution.
 */

#ifndef TKDROP_H
#define TKDROP_H

#include <tcl.h>
#include <tk.h>

/*
 * Register a Tk window as a file drop target.
 * When a file is dropped, generates <<DropFile>> with -data set to the path.
 *
 * Returns TCL_OK on success, TCL_ERROR on failure (with error in interp).
 */
int teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                              const char *widget_path);

#endif /* TKDROP_H */
