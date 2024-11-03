pub const c = @import("c.zig");

test "Import" {
    const std = @import("std");
    std.testing.refAllDecls(@import("types/root.zig"));
    std.testing.refAllDecls(@import("tokenize/root.zig"));
}
