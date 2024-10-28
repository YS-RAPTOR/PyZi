const c = @import("PyZi").c;
const config = @import("config");

export fn PyInit_Sim() [*c]c.PyObject {
    return null;
}

const std = @import("std");

test "First Test" {
    std.debug.print("Hello, {s}!\n", .{config.name});
}
