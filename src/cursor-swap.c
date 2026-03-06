/*
 * cursor-swap — live-replace all X11 cursors with a new Xcursor theme
 * Uses XFixes to swap cursor contents server-side so already-open windows
 * get the new cursor without restarting.
 *
 * Usage: cursor-swap <theme> [size]
 * Compile: gcc -O2 -o cursor-swap cursor-swap.c -lX11 -lXfixes -lXcursor
 */

#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/Xcursor/Xcursor.h>
#include <X11/extensions/Xfixes.h>

static const char *names[] = {
    "alias", "all-scroll", "arrow",
    "bd_double_arrow", "bottom_left_corner", "bottom_right_corner",
    "bottom_side", "bottom_tee",
    "cell", "center_ptr", "circle", "closedhand", "color-picker",
    "col-resize", "context-menu", "copy", "cross", "crossed_circle",
    "crosshair", "cross_reverse",
    "default", "diamond_cross", "dnd-ask", "dnd-copy", "dnd-link",
    "dnd-move", "dnd_no_drop", "dnd-none", "dotbox", "dot_box_mask",
    "double_arrow", "down-arrow", "draft", "draft_large", "draft_small",
    "draped_box",
    "e-resize", "ew-resize",
    "fd_double_arrow", "fleur", "forbidden",
    "grab", "grabbing",
    "hand1", "hand2", "h_double_arrow", "help",
    "ibeam", "icon",
    "left-arrow", "left_ptr", "left_ptr_help", "left_ptr_watch",
    "left_side", "left_tee", "link", "ll_angle", "lr_angle",
    "move",
    "ne-resize", "nesw-resize", "no-drop", "not-allowed",
    "n-resize", "ns-resize", "nw-resize", "nwse-resize",
    "openhand",
    "pencil", "pirate", "plus", "pointer", "pointer-move",
    "pointing_hand", "progress",
    "question_arrow",
    "right-arrow", "right_ptr", "right_side", "right_tee", "row-resize",
    "sb_down_arrow", "sb_h_double_arrow", "sb_left_arrow",
    "sb_right_arrow", "sb_up_arrow", "sb_v_double_arrow",
    "se-resize", "size_all", "size_bdiag", "size_fdiag",
    "size-hor", "size_hor", "size-ver", "size_ver",
    "split_h", "split_v", "s-resize", "sw-resize",
    "target", "tcross", "text", "top_left_arrow",
    "top_left_corner", "top_right_corner", "top_side", "top_tee",
    "ul_angle", "up-arrow", "ur_angle",
    "v_double_arrow", "vertical-text",
    "wait", "watch", "whats_this", "w-resize",
    "x-cursor", "X_cursor", "xterm",
    "zoom-in", "zoom-out",
    NULL
};

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: cursor-swap <theme> [size]\n");
        return 1;
    }

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "cursor-swap: cannot open display\n");
        return 1;
    }

    XcursorSetTheme(dpy, argv[1]);
    if (argc >= 3)
        XcursorSetDefaultSize(dpy, atoi(argv[2]));

    for (const char **n = names; *n; n++) {
        Cursor c = XcursorLibraryLoadCursor(dpy, *n);
        if (c) {
            XFixesChangeCursorByName(dpy, c, *n);
            XFreeCursor(dpy, c);
        }
    }

    XFlush(dpy);
    XCloseDisplay(dpy);
    return 0;
}
