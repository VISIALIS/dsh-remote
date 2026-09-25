// widget_entry.c — Thin C shim for the widget extension entry point.
//
// This file provides a C function "widget_extension_main" that calls the
// real NSExtensionMain from Foundation.  Calling it through this shim lets
// Swift main.swift avoid declaring NSExtensionMain with @_silgen_name, which
// would shadow Foundation's symbol and cause infinite recursion.
//
// NSExtensionMain has a plain C signature — no Objective-C types needed.

#include <stdint.h>

// NSExtensionMain is a plain C function exported by Foundation.framework.
// Declaring it as extern "C" / extern is sufficient; no ObjC runtime needed.
extern int NSExtensionMain(int argc, const char * _Nullable * _Null_unspecified argv);

int widget_extension_main(int argc, const char * _Nullable * _Null_unspecified argv) {
    return NSExtensionMain(argc, argv);
}
