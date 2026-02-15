/* tkdrop_macos.m - macOS file drop target via Cocoa NSDraggingDestination
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as reference.
 * See THIRD_PARTY_NOTICES for attribution.
 */

#import <Cocoa/Cocoa.h>
#include <tcl.h>
#include <tk.h>
#include "tkdrop.h"

#ifndef MAC_OSX_TK
#define MAC_OSX_TK
#endif
#include "tkPlatDecls.h"

/* --------------------------------------------------------- */

@interface TeekDropView : NSView <NSDraggingDestination>
{
    Tcl_Interp *_interp;
    char *_widgetPath;
}
- (instancetype)initWithFrame:(NSRect)frame
                       interp:(Tcl_Interp *)interp
                   widgetPath:(const char *)widgetPath;
@end

@implementation TeekDropView

- (instancetype)initWithFrame:(NSRect)frame
                       interp:(Tcl_Interp *)interp
                   widgetPath:(const char *)widgetPath
{
    self = [super initWithFrame:frame];
    if (self) {
        _interp = interp;
        _widgetPath = strdup(widgetPath);
        [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (void)dealloc
{
    free(_widgetPath);
    [super dealloc];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([pb canReadObjectForClasses:@[[NSURL class]]
                            options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls || [urls count] == 0) {
        return NO;
    }

    for (NSURL *url in urls) {
        NSString *path = [url path];
        if (!path) continue;

        const char *utf8 = [path UTF8String];

        /* Generate <<DropFile>> virtual event with -data */
        Tcl_Obj *script = Tcl_ObjPrintf(
            "event generate %s <<DropFile>> -data {%s}",
            _widgetPath, utf8);
        Tcl_IncrRefCount(script);
        Tcl_EvalObjEx(_interp, script, TCL_EVAL_GLOBAL);
        Tcl_DecrRefCount(script);
    }

    return YES;
}

/* Allow the drop view to be transparent to mouse events when not dragging */
- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

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

    void *nswindow = Tk_MacOSXGetNSWindowForDrawable(drawable);
    if (!nswindow) {
        Tcl_SetResult(interp, "could not get NSWindow", TCL_STATIC);
        return TCL_ERROR;
    }

    NSWindow *window = (__bridge NSWindow *)nswindow;
    NSView *contentView = [window contentView];
    if (!contentView) {
        Tcl_SetResult(interp, "could not get content view", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Check if we already registered a drop view on this window */
    for (NSView *subview in [contentView subviews]) {
        if ([subview isKindOfClass:[TeekDropView class]]) {
            return TCL_OK; /* Already registered */
        }
    }

    TeekDropView *dropView = [[TeekDropView alloc]
        initWithFrame:[contentView bounds]
               interp:interp
           widgetPath:widget_path];

    [contentView addSubview:dropView];

    return TCL_OK;
}
