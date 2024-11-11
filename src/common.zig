const std = @import("std");
const builtin = @import("builtin");

pub fn Error(comptime fmt: []const u8, comptime args: anytype, comptime e: anyerror) !void {
    comptime {
        if (builtin.is_test) {
            return e;
        } else {
            @compileError(std.fmt.comptimePrint(fmt, args));
        }
    }
}

pub fn inStrArray(array: [][]const u8, value: []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, item, value)) {
            return true;
        }
    }
    return false;
}
