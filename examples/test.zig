const config = @import("config");

const std = @import("std");

test "First Test" {
    std.debug.print("Hello, {s}!\n", .{config.name});
}
