/* tkdrop_x11.c - X11 file drop target via XDND protocol
 *
 * Implements the XDND (version 5) drop target protocol for receiving
 * file drops from X11 desktop environments. Handles XdndEnter,
 * XdndPosition, XdndDrop client messages and selection transfer.
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 * See THIRD_PARTY_NOTICES for attribution.
 */

#include <tcl.h>
#include <tk.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "tkdrop.h"

#define XDND_VERSION 5

/* Per-window drop target state */
typedef struct {
    Tcl_Interp *interp;
    char *widget_path;
    Tk_Window tkwin;
    Display *display;
    Window window;
    /* XDND atoms (cached) */
    Atom xdnd_aware;
    Atom xdnd_enter;
    Atom xdnd_position;
    Atom xdnd_status;
    Atom xdnd_drop;
    Atom xdnd_finished;
    Atom xdnd_selection;
    Atom xdnd_type_list;
    Atom xdnd_action_copy;
    Atom text_uri_list;
    Atom teek_drop_prop;
    /* State during drag */
    Window source_window;
    int has_uri_list;
} TeekXdndState;

/* Decode a %XX hex escape in a URI, return decoded char or -1 on error */
static int
hex_decode(const char *s)
{
    int hi, lo;
    hi = s[0];
    lo = s[1];
    if (hi >= '0' && hi <= '9') hi -= '0';
    else if (hi >= 'a' && hi <= 'f') hi = hi - 'a' + 10;
    else if (hi >= 'A' && hi <= 'F') hi = hi - 'A' + 10;
    else return -1;
    if (lo >= '0' && lo <= '9') lo -= '0';
    else if (lo >= 'a' && lo <= 'f') lo = lo - 'a' + 10;
    else if (lo >= 'A' && lo <= 'F') lo = lo - 'A' + 10;
    else return -1;
    return (hi << 4) | lo;
}

/* Convert a file:// URI to a filesystem path in-place.
 * Strips the file:// prefix and decodes %XX escapes.
 * Returns pointer to the path within the buffer, or NULL if not a file URI. */
static char *
uri_to_path(char *uri)
{
    char *src, *dst;

    /* Strip file:// prefix */
    if (strncmp(uri, "file://", 7) == 0) {
        src = uri + 7;
        /* Skip optional hostname (file://localhost/path -> /path) */
        if (*src != '/' && strncmp(src, "localhost", 9) == 0) {
            src += 9;
        }
    } else {
        return NULL;
    }

    /* URL-decode in place */
    dst = src;
    while (*src) {
        if (*src == '%' && src[1] && src[2]) {
            int ch = hex_decode(src + 1);
            if (ch >= 0) {
                *dst++ = (char)ch;
                src += 3;
                continue;
            }
        }
        *dst++ = *src++;
    }
    *dst = '\0';

    return uri + 7 + (uri[7] != '/') * 9; /* return start of decoded path */
}

/* Send XdndStatus response to source */
static void
send_xdnd_status(TeekXdndState *st, int accept)
{
    XClientMessageEvent msg;
    memset(&msg, 0, sizeof(msg));
    msg.type = ClientMessage;
    msg.display = st->display;
    msg.window = st->source_window;
    msg.message_type = st->xdnd_status;
    msg.format = 32;
    msg.data.l[0] = st->window;          /* target window */
    msg.data.l[1] = accept ? 1 : 0;      /* bit 0 = accept */
    msg.data.l[2] = 0;                    /* empty rectangle */
    msg.data.l[3] = 0;
    msg.data.l[4] = accept ? st->xdnd_action_copy : 0;

    XSendEvent(st->display, st->source_window, False, NoEventMask,
               (XEvent *)&msg);
}

/* Send XdndFinished to source */
static void
send_xdnd_finished(TeekXdndState *st, int success)
{
    XClientMessageEvent msg;
    memset(&msg, 0, sizeof(msg));
    msg.type = ClientMessage;
    msg.display = st->display;
    msg.window = st->source_window;
    msg.message_type = st->xdnd_finished;
    msg.format = 32;
    msg.data.l[0] = st->window;
    msg.data.l[1] = success ? 1 : 0;
    msg.data.l[2] = success ? st->xdnd_action_copy : 0;

    XSendEvent(st->display, st->source_window, False, NoEventMask,
               (XEvent *)&msg);
}

/* Process dropped data (text/uri-list) and generate a single <<DropFile>> event */
static void
process_uri_list(TeekXdndState *st, const char *data, unsigned long len)
{
    char *buf = (char *)malloc(len + 1);
    if (!buf) return;
    memcpy(buf, data, len);
    buf[len] = '\0';

    /* Build a Tcl list of all dropped file paths */
    Tcl_Obj *listObj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(listObj);

    /* text/uri-list: one URI per line, \r\n separated, # lines are comments */
    char *line = buf;
    while (line && *line) {
        char *eol = strstr(line, "\r\n");
        if (eol) *eol = '\0';

        /* Skip comments and empty lines */
        if (*line && *line != '#') {
            char *uri_copy = strdup(line);
            if (uri_copy) {
                char *path = uri_to_path(uri_copy);
                if (path && *path) {
                    Tcl_ListObjAppendElement(NULL, listObj,
                        Tcl_NewStringObj(path, -1));
                }
                free(uri_copy);
            }
        }

        line = eol ? eol + 2 : NULL;
    }

    /* Generate single <<DropFile>> event with all paths as a Tcl list */
    Tcl_Obj *script = Tcl_ObjPrintf(
        "event generate %s <<DropFile>> -data {%s}",
        st->widget_path, Tcl_GetString(listObj));
    Tcl_IncrRefCount(script);
    Tcl_EvalObjEx(st->interp, script, TCL_EVAL_GLOBAL);
    Tcl_DecrRefCount(script);
    Tcl_DecrRefCount(listObj);

    free(buf);
}

/* Tk event handler for ClientMessage and SelectionNotify */
static int
xdnd_event_handler(ClientData clientData, XEvent *eventPtr)
{
    TeekXdndState *st = (TeekXdndState *)clientData;

    if (eventPtr->type == ClientMessage) {
        XClientMessageEvent *cm = &eventPtr->xclient;

        if (cm->message_type == st->xdnd_enter) {
            st->source_window = (Window)cm->data.l[0];
            int version = (cm->data.l[1] >> 24) & 0xFF;
            if (version > XDND_VERSION) return 0;

            /* Check if text/uri-list is among offered types */
            st->has_uri_list = 0;
            int more_than_3 = cm->data.l[1] & 1;

            if (more_than_3) {
                /* Fetch XdndTypeList property from source */
                Atom type;
                int format;
                unsigned long count, remaining;
                unsigned char *prop_data = NULL;

                XGetWindowProperty(st->display, st->source_window,
                    st->xdnd_type_list, 0, 1024, False, XA_ATOM,
                    &type, &format, &count, &remaining, &prop_data);

                if (prop_data) {
                    Atom *types = (Atom *)prop_data;
                    unsigned long i;
                    for (i = 0; i < count; i++) {
                        if (types[i] == st->text_uri_list) {
                            st->has_uri_list = 1;
                            break;
                        }
                    }
                    XFree(prop_data);
                }
            } else {
                /* Types are in data.l[2..4] */
                int i;
                for (i = 2; i <= 4; i++) {
                    if ((Atom)cm->data.l[i] == st->text_uri_list) {
                        st->has_uri_list = 1;
                        break;
                    }
                }
            }
            return 1;
        }

        if (cm->message_type == st->xdnd_position) {
            send_xdnd_status(st, st->has_uri_list);
            return 1;
        }

        if (cm->message_type == st->xdnd_drop) {
            if (st->has_uri_list) {
                Time timestamp = (Time)cm->data.l[2];
                XConvertSelection(st->display, st->xdnd_selection,
                    st->text_uri_list, st->teek_drop_prop,
                    st->window, timestamp);
            } else {
                send_xdnd_finished(st, 0);
            }
            return 1;
        }
    }

    if (eventPtr->type == SelectionNotify) {
        XSelectionEvent *sel = &eventPtr->xselection;
        if (sel->property == st->teek_drop_prop) {
            Atom type;
            int format;
            unsigned long count, remaining;
            unsigned char *data = NULL;

            XGetWindowProperty(st->display, st->window,
                st->teek_drop_prop, 0, 65536, True, AnyPropertyType,
                &type, &format, &count, &remaining, &data);

            if (data && count > 0) {
                process_uri_list(st, (const char *)data, count);
            }
            if (data) XFree(data);

            send_xdnd_finished(st, 1);
            return 1;
        }
    }

    return 0;
}

/* Tk generic event handler wrapper */
static int
xdnd_generic_handler(ClientData clientData, XEvent *eventPtr)
{
    return xdnd_event_handler(clientData, eventPtr);
}

int
teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                          const char *widget_path)
{
    Display *display = Tk_Display(tkwin);
    Window window = Tk_WindowId(tkwin);

    if (!display || !window) {
        Tcl_SetResult(interp, "window has no X11 display/id", TCL_STATIC);
        return TCL_ERROR;
    }

    TeekXdndState *st = (TeekXdndState *)calloc(1, sizeof(TeekXdndState));
    if (!st) {
        Tcl_SetResult(interp, "out of memory", TCL_STATIC);
        return TCL_ERROR;
    }

    st->interp = interp;
    st->widget_path = strdup(widget_path);
    st->tkwin = tkwin;
    st->display = display;
    st->window = window;

    /* Cache atoms */
    st->xdnd_aware      = Tk_InternAtom(tkwin, "XdndAware");
    st->xdnd_enter       = Tk_InternAtom(tkwin, "XdndEnter");
    st->xdnd_position    = Tk_InternAtom(tkwin, "XdndPosition");
    st->xdnd_status      = Tk_InternAtom(tkwin, "XdndStatus");
    st->xdnd_drop        = Tk_InternAtom(tkwin, "XdndDrop");
    st->xdnd_finished    = Tk_InternAtom(tkwin, "XdndFinished");
    st->xdnd_selection   = Tk_InternAtom(tkwin, "XdndSelection");
    st->xdnd_type_list   = Tk_InternAtom(tkwin, "XdndTypeList");
    st->xdnd_action_copy = Tk_InternAtom(tkwin, "XdndActionCopy");
    st->text_uri_list    = Tk_InternAtom(tkwin, "text/uri-list");
    st->teek_drop_prop   = Tk_InternAtom(tkwin, "TeekDropData");

    /* Set XdndAware property (version 5) */
    Atom version = XDND_VERSION;
    XChangeProperty(display, window, st->xdnd_aware, XA_ATOM, 32,
                    PropModeReplace, (unsigned char *)&version, 1);

    /* Register generic event handler for ClientMessage + SelectionNotify */
    Tk_CreateGenericHandler(xdnd_generic_handler, (ClientData)st);

    return TCL_OK;
}
