const std = @import("std");
const builtin = @import("builtin");
const def = @import("definitions.zig");

fn inStrArray(array: [][]const u8, value: []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, item, value)) {
            return true;
        }
    }
    return false;
}

fn Error(comptime fmt: []const u8, comptime args: anytype, comptime e: Errors) !void {
    comptime {
        if (builtin.is_test) {
            return e;
        } else {
            @compileError(std.fmt.comptimePrint(fmt, args));
        }
    }
}

pub const Errors = error{
    MissingRequiredField,
    InvalidRootModule,
    UnknownDeclaration,
};

fn isValidRootModule(definition: type, name: []const u8) !void {
    const type_info = @typeInfo(definition);
    if (type_info != .Struct) {
        return Error(
            "Root module {s} must be a struct",
            .{name},
            Errors.InvalidRootModule,
        );
    }

    if (!@hasDecl(definition, "Type")) {
        return Error(
            "Root module {s} is missing required declaration: Type",
            .{name},
            Errors.MissingRequiredField,
        );
    }

    if (@field(definition, "Type") != .Module) {
        return Error(
            "Root module {s} must be of type Module",
            .{name},
            Errors.InvalidRootModule,
        );
    }
}

fn handleDeclaration(definition: type, decl: std.builtin.Type.Declaration) !union(enum) {
    PyZiDeclaration: def.Declaration.SpecialDecls,
    Declaration: def.Declaration,
    Fn: def.Fn,
    Container: def.Container,
} {
    // TODO: Check for types
    const decl_type_info = @typeInfo(@TypeOf(@field(definition, decl.name)));
    if (decl_type_info != .Type and decl_type_info != .Fn) {
        // If it is a special declaration
        if (inStrArray(@constCast(&def.Declaration.all_special_decls), decl.name)) {
            const special_decl = @field(def.Declaration.SpecialDecls, decl.name);

            if (special_decl.isPyZi()) {
                return .{
                    .PyZiDeclaration = special_decl,
                };
            } else {
                return .{
                    .Declaration = def.Declaration{
                        .type = .{ .Special = special_decl },
                        .name = decl.name,
                    },
                };
            }
        }

        // Can only be a class attribute
        const is_const = @typeInfo(@TypeOf(&@field(definition, decl.name))).Pointer.is_const;
        return .{
            .Declaration = def.Declaration{
                .type = .{ .ClassAttribute = if (is_const) .Const else .Var },
                .name = decl.name,
            },
        };
    }

    // Check if it is a Fn
    if (decl_type_info == .Fn) {
        // TODO: Fill out function information
        const fn_type: def.Fn.Types = if (inStrArray(@constCast(&def.Fn.all_special_names), decl.name)) blk: {
            break :blk .Special;
        } else blk: {
            if (decl_type_info.Fn.params.len < 1) break :blk .Static;
            if (decl_type_info.Fn.params[0].type == *definition) {
                break :blk .Class;
            } else {
                break :blk .Static;
            }
        };

        return .{
            .Fn = .{
                .name = decl.name,
                .type = fn_type,
            },
        };
    }

    const decl_info = @typeInfo(@field(definition, decl.name));
    if (decl_info == .Struct) {
        return .{
            .Container = try tokenize(@field(definition, decl.name), decl.name, false),
        };
    }

    return Error(
        "Unknown Declaration: {s} of type {any}",
        .{ decl.name, decl_info },
        Errors.UnknownDeclaration,
    );
}

pub fn tokenize(definition: type, comptime name: []const u8, comptime is_root: bool) Errors!def.Container {
    comptime {
        if (is_root) try isValidRootModule(definition, name);
        const type_info = @typeInfo(definition);

        if (type_info != .Struct) {
            return Error(
                "Root Module {s} must be a struct",
                .{name},
                Errors.InvalidRootModule,
            );
        }

        const data = type_info.Struct;
        var container: def.Container = .{
            .name = name,
            .type = undefined,
            .decls = &[_]def.Declaration{},
            .subs = &[_]def.Container{},
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{},
        };

        var all_declarations: [data.decls.len][]const u8 = .{""} ** data.decls.len;
        for (0..data.decls.len) |i| {
            all_declarations[i] = data.decls[i].name;
        }

        // Check if Required Declarations are present
        for (def.Declaration.required_decls) |required| {
            if (!inStrArray(&all_declarations, required)) {
                return Error(
                    "Struct {s} is missing required declaration: {s}",
                    .{ name, required },
                    Errors.MissingRequiredField,
                );
            }
        }

        // Handle Other Declarations
        for (data.decls) |decl| {
            switch (try handleDeclaration(definition, decl)) {
                .Declaration => |res| container.decls = container.decls ++ .{res},
                .Fn => |res| container.fns = container.fns ++ .{res},
                .Container => |res| container.subs = container.subs ++ .{res},
                .PyZiDeclaration => |res| @field(container, res.fieldNamePyZi()) = @field(definition, decl.name),
            }
        }
        return container;
    }
}

test "Test Basic Root Module" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
    };

    comptime {
        _ = try tokenize(
            root,
            "Root",
            true,
        );
    }
}

test "Test Basic Root Without Type" {
    const root = struct {
        pub const Typ: def.Container.Type = .Module;
    };

    comptime {
        try std.testing.expectError(Errors.MissingRequiredField, tokenize(
            root,
            "Root",
            true,
        ));
    }
}
test "Test Basic Root With Wrong Type" {
    const root = struct {
        pub const Type: def.Container.Type = .Class;
    };

    comptime {
        try std.testing.expectError(Errors.InvalidRootModule, tokenize(
            root,
            "Root",
            true,
        ));
    }
}

test "Test Basic Root Other Declarations" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
        pub const PhaseType: def.Container.PhaseType = .MultiPhase;
        pub const a: u32 = 1;
        pub var b: u32 = 2;
        pub const doc =
            \\ Cringe Root Module
            \\ Cringe Root Module
            \\ Cringe Root Module
        ;
    };

    comptime {
        var expected = std.mem.zeroes(def.Container);
        expected.type = .Module;
        expected.phase_type = .MultiPhase;
        expected.name = "Root";

        expected.decls = &[_]def.Declaration{
            .{
                .type = .{ .ClassAttribute = .Const },
                .name = "a",
            },
            .{
                .type = .{ .ClassAttribute = .Var },
                .name = "b",
            },
            .{
                .type = .{ .Special = .doc },
                .name = "doc",
            },
        };

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}

test "Test Basic Root With Sub Modules" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
        pub const Sub = struct {
            pub const Type: def.Container.Type = .Class;
        };
    };

    comptime {
        var expected = std.mem.zeroes(def.Container);
        expected.type = .Module;
        expected.name = "Root";

        var sub = std.mem.zeroes(def.Container);
        sub.type = .Class;
        sub.name = "Sub";

        expected.subs = &[_]def.Container{sub};

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
test "Test Basic Root With Functions" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;

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

    comptime {
        var expected = std.mem.zeroes(def.Container);
        expected.type = .Module;
        expected.name = "Root";
        expected.fns = &[_]def.Fn{
            .{
                .name = "init",
                .type = .Special,
            },
            .{
                .name = "cringe",
                .type = .Class,
            },
            .{
                .name = "dumb",
                .type = .Static,
            },
            .{
                .name = "dumb1",
                .type = .Static,
            },

            .{
                .name = "dumb2",
                .type = .Static,
            },
        };

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
test "Test Nested Module With Delarations and Functions" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
        pub const Sub = struct {
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
    };

    comptime {
        var expected = std.mem.zeroes(def.Container);
        expected.type = .Module;
        expected.phase_type = .SinglePhase;
        expected.name = "Root";

        var sub = std.mem.zeroes(def.Container);
        sub.type = .Module;
        sub.phase_type = .MultiPhase;
        sub.name = "Sub";

        sub.decls = &[_]def.Declaration{
            .{
                .type = .{ .ClassAttribute = .Const },
                .name = "a",
            },
            .{
                .type = .{ .ClassAttribute = .Var },
                .name = "b",
            },
            .{
                .type = .{ .Special = .doc },
                .name = "doc",
            },
        };
        sub.fns = &[_]def.Fn{
            .{
                .name = "init",
                .type = .Special,
            },
            .{
                .name = "cringe",
                .type = .Class,
            },
            .{
                .name = "dumb",
                .type = .Static,
            },
            .{
                .name = "dumb1",
                .type = .Static,
            },

            .{
                .name = "dumb2",
                .type = .Static,
            },
        };
        expected.subs = &[_]def.Container{sub};

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
