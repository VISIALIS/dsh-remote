// main.swift — Widget extension entry point.
//
// WidgetKit extensions must be launched by the system extension host via
// NSExtensionMain (from Foundation). Using @main / SwiftUI.WidgetBundle.main()
// as the process entry point causes ExtensionFoundation to crash (brk #0x1)
// because it requires the extension host to have set up the runtime context.
//
// We call NSExtensionMain via a thin C shim (widget_entry.c) rather than
// declaring it with @_silgen_name, which would create a circular symbol
// and cause infinite recursion (stack overflow).

import Foundation

// Forward-declare the C shim in widget_entry.c, which calls NSExtensionMain.
@_silgen_name("widget_extension_main")
func widgetExtensionMain(_ argc: Int32,
                         _ argv: UnsafePointer<UnsafePointer<CChar>?>?) -> Int32

CommandLine.unsafeArgv.withMemoryRebound(
    to: UnsafePointer<CChar>?.self,
    capacity: Int(CommandLine.argc) + 1
) { argv in
    _ = widgetExtensionMain(CommandLine.argc, argv)
}
