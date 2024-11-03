// Module
const std = @import("std");
const def = @import("../tokenize/definitions.zig");
const tok = @import("../tokenize/tokenizer.zig");
const config = @import("config");

pub fn initializeModule(definition: type) !void {
    comptime {
        const tokens = try tok.tokenize(
            definition,
            config.module_name,
            true,
        );
        _ = tokens;
    }
}

pub fn debugModule(definition: type) !void {
    const msg: []const u8 = blk: {
        comptime {
            const tokens = try tok.tokenize(
                definition,
                config.module_name,
                true,
            );
            break :blk std.fmt.comptimePrint(
                "{}",
                .{tokens},
            );
        }
    };

    std.debug.print("{s}\n", .{msg});
}

test "Simple Test" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
        pub const Sub1 = struct {
            pub const Type: def.Container.Type = .Module;
            pub const PhaseType: def.Container.PhaseType = .MultiPhase;
            pub const a: u32 = 1;
            pub var b: u32 = 2;
            pub const doc =
                \\ Cringe Root Module
                \\ Cringe Root Module
                \\ Cringe Root Module
            ;
            pub fn init() void {}
            pub fn cringe(self: *@This()) void {
                _ = self;
            }
            pub fn dumb() void {}
            pub fn dumb1(hey: u32) void {
                _ = hey;
            }
            pub fn dumb2(hey: u32, hay: i32) void {
                _ = hey;
                _ = hay;
            }
        };

        pub const Sub2 = struct {
            pub const Type: def.Container.Type = .Class;
            a: u32,
            b: struct {
                val: u32,
            },

            c: struct {
                val: u32,
                pub fn get(self: @This()) u32 {
                    return self.val;
                }
            },
            d: struct {
                val: u32,
                pub fn set(self: @This()) void {
                    return self.val;
                }
            },
            e: struct {
                val: u32,
                pub fn get(self: @This()) u32 {
                    return self.val;
                }
                pub fn set(self: @This()) void {
                    return self.val;
                }
            },
        };
    };

    try debugModule(root);
}
