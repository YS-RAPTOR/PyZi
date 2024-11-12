pub const c = @import("c.zig");

test "Import" {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@import("types/root.zig"));
    std.testing.refAllDeclsRecursive(@import("tokenize/root.zig"));
}
