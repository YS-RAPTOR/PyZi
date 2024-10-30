test "Import" {
    const std = @import("std");
    std.testing.refAllDecls(@import("tokenize/root.zig"));
}
