/* tkdrop_win.c - Windows file drop target via OLE IDropTarget
 *
 * Uses the OLE drag-and-drop API (RegisterDragDrop/IDropTarget) for
 * flexible drop support. Extracts file paths from CF_HDROP format and
 * generates <<DropFile>> virtual events.
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 * See THIRD_PARTY_NOTICES for attribution.
 */

#include <tcl.h>
#include <tk.h>
#include "tkdrop.h"

#ifdef _WIN32

#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <shellapi.h>
#include "tkPlatDecls.h"

/* --------------------------------------------------------- */
/* IDropTarget implementation in C via COM vtable             */
/* --------------------------------------------------------- */

typedef struct TeekDropTarget {
    IDropTargetVtbl *lpVtbl;
    LONG ref_count;
    Tcl_Interp *interp;
    char *widget_path;
    HWND hwnd;
} TeekDropTarget;

static HRESULT STDMETHODCALLTYPE
tdt_QueryInterface(IDropTarget *self, REFIID riid, void **ppv)
{
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDropTarget)) {
        *ppv = self;
        IDropTarget_AddRef(self);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
tdt_AddRef(IDropTarget *self)
{
    TeekDropTarget *tdt = (TeekDropTarget *)self;
    return InterlockedIncrement(&tdt->ref_count);
}

static ULONG STDMETHODCALLTYPE
tdt_Release(IDropTarget *self)
{
    TeekDropTarget *tdt = (TeekDropTarget *)self;
    LONG count = InterlockedDecrement(&tdt->ref_count);
    if (count == 0) {
        free(tdt->widget_path);
        free(tdt);
    }
    return count;
}

/* Check if the drag contains files */
static BOOL
has_file_data(IDataObject *pDataObj)
{
    FORMATETC fmt = { CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    return IDataObject_QueryGetData(pDataObj, &fmt) == S_OK;
}

static HRESULT STDMETHODCALLTYPE
tdt_DragEnter(IDropTarget *self, IDataObject *pDataObj, DWORD grfKeyState,
              POINTL pt, DWORD *pdwEffect)
{
    if (has_file_data(pDataObj)) {
        *pdwEffect = DROPEFFECT_COPY;
    } else {
        *pdwEffect = DROPEFFECT_NONE;
    }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE
tdt_DragOver(IDropTarget *self, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect)
{
    *pdwEffect = DROPEFFECT_COPY;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE
tdt_DragLeave(IDropTarget *self)
{
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE
tdt_Drop(IDropTarget *self, IDataObject *pDataObj, DWORD grfKeyState,
         POINTL pt, DWORD *pdwEffect)
{
    TeekDropTarget *tdt = (TeekDropTarget *)self;
    FORMATETC fmt = { CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    STGMEDIUM stg;
    HRESULT hr;

    *pdwEffect = DROPEFFECT_NONE;

    hr = IDataObject_GetData(pDataObj, &fmt, &stg);
    if (FAILED(hr)) return hr;

    HDROP hDrop = (HDROP)GlobalLock(stg.hGlobal);
    if (!hDrop) {
        ReleaseStgMedium(&stg);
        return E_FAIL;
    }

    UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, NULL, 0);
    UINT i;

    /* Build a Tcl list of all dropped file paths */
    Tcl_Obj *listObj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(listObj);

    for (i = 0; i < count; i++) {
        WCHAR wpath[MAX_PATH];
        if (DragQueryFileW(hDrop, i, wpath, MAX_PATH) == 0) continue;

        /* Convert wide string to UTF-8 for Tcl */
        int utf8_len = WideCharToMultiByte(CP_UTF8, 0, wpath, -1,
                                           NULL, 0, NULL, NULL);
        if (utf8_len <= 0) continue;

        char *utf8 = (char *)malloc(utf8_len);
        if (!utf8) continue;

        WideCharToMultiByte(CP_UTF8, 0, wpath, -1, utf8, utf8_len, NULL, NULL);
        Tcl_ListObjAppendElement(NULL, listObj,
            Tcl_NewStringObj(utf8, -1));
        free(utf8);
    }

    /* Generate single <<DropFile>> event with all paths as a Tcl list */
    Tcl_Obj *script = Tcl_ObjPrintf(
        "event generate %s <<DropFile>> -data {%s}",
        tdt->widget_path, Tcl_GetString(listObj));
    Tcl_IncrRefCount(script);
    Tcl_EvalObjEx(tdt->interp, script, TCL_EVAL_GLOBAL);
    Tcl_DecrRefCount(script);
    Tcl_DecrRefCount(listObj);

    GlobalUnlock(stg.hGlobal);
    ReleaseStgMedium(&stg);
    *pdwEffect = DROPEFFECT_COPY;
    return S_OK;
}

/* COM vtable */
static IDropTargetVtbl teek_drop_vtbl = {
    tdt_QueryInterface,
    tdt_AddRef,
    tdt_Release,
    tdt_DragEnter,
    tdt_DragOver,
    tdt_DragLeave,
    tdt_Drop
};

/* --------------------------------------------------------- */

int
teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                          const char *widget_path)
{
    Drawable drawable = Tk_WindowId(tkwin);
    if (!drawable) {
        Tcl_SetResult(interp, "window has no native handle", TCL_STATIC);
        return TCL_ERROR;
    }

    HWND hwnd = Tk_GetHWND(drawable);
    if (!hwnd) {
        Tcl_SetResult(interp, "could not get HWND", TCL_STATIC);
        return TCL_ERROR;
    }

    HRESULT hr = OleInitialize(NULL);
    if (FAILED(hr)) {
        Tcl_SetResult(interp, "OleInitialize failed", TCL_STATIC);
        return TCL_ERROR;
    }

    TeekDropTarget *tdt = (TeekDropTarget *)malloc(sizeof(TeekDropTarget));
    if (!tdt) {
        Tcl_SetResult(interp, "out of memory", TCL_STATIC);
        return TCL_ERROR;
    }

    tdt->lpVtbl = &teek_drop_vtbl;
    tdt->ref_count = 1;
    tdt->interp = interp;
    tdt->widget_path = strdup(widget_path);
    tdt->hwnd = hwnd;

    hr = RegisterDragDrop(hwnd, (IDropTarget *)tdt);
    if (FAILED(hr)) {
        free(tdt->widget_path);
        free(tdt);
        if (hr == DRAGDROP_E_ALREADYREGISTERED) {
            return TCL_OK; /* Already registered */
        }
        Tcl_SetResult(interp, "RegisterDragDrop failed", TCL_STATIC);
        return TCL_ERROR;
    }

    return TCL_OK;
}

#else

int
teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                          const char *widget_path)
{
    Tcl_SetResult(interp, "file drop not supported on this platform", TCL_STATIC);
    return TCL_ERROR;
}

#endif /* _WIN32 */
