const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");

// TODO: Better formatting for these classes

const Container = struct {
    const PhaseType = enum {
        SinglePhase, // Default
        MultiPhase,
    };

    const Type = enum {
        Module,
        Class, // TODO: Check if classes can be in multi-phase
    };

    type: Type,

    phase_type: PhaseType = .SinglePhase,
    name: []const u8,

    decls: []const Declaration,
    sub_containers: []const @This(),
    fns: []const Fn,

    fields: []const Field,
};

const Declaration = struct {
    const SpecialDecls = enum {
        doc,
        clear,
        traverse,
        free,
        Type,
        PhaseType,

        fn isPyZi(self: *const @This()) bool {
            switch (self.*) {
                .Type,
                .PhaseType,
                => return true,
                .doc,
                .clear,
                .traverse,
                .free,
                => return false,
            }
        }

        fn isPython(self: *const @This()) bool {
            return !self.isPyZi();
        }

        fn isRequired(self: *const @This()) bool {
            switch (self.*) {
                .Type => return true,
                else => return false,
            }
        }

        fn fieldNamePyZi(self: *const @This()) []const u8 {
            switch (self.*) {
                .Type => return "type",
                .PhaseType => return "phase_type",
                else => unreachable,
            }
        }
    };

    const all_special_decls = blk: {
        const len = @typeInfo(SpecialDecls).Enum.fields.len;
        var fields: [len]SpecialDecls = .{.doc} ** len;

        for (0..len) |i| {
            fields[i] = @enumFromInt(i);
        }

        break :blk fields;
    };

    const Types = union(enum) {
        Special: SpecialDecls, // Special PyZi/Python Declarations: Has special name.
        // Class Attribute: Can be accessed in zig and python.
        // If not special and is public it is assumed to be class/module attribute/constant.
        ClassAttribute: enum(u1) {
            Const,
            Var,
        },
    };

    type: Types,
    name: []const u8,
};

const Field = struct {
    const Types = union(enum) {
        Normal, // Can only be accessed in zig
        InstanceAttribute, // Can be accessed in zig and python
        Property: struct {}, // Figure out what properties are
    };
    type: Types,
    name: []const u8,
};

const Fn = struct {
    const SpecialFns = enum {
        init,
        lhs, // Research all special functions
    };

    const all_special_names = blk: {
        const len = @typeInfo(SpecialFns).Enum.fields.len;
        var fields: [len][]const u8 = .{""} ** len;

        for (0..len) |i| {
            fields[i] = @tagName(@as(SpecialFns, @enumFromInt(i)));
        }

        break :blk fields;
    };

    const Types = union(enum) {
        Special, // Has special name
        Static, // No self
        Class, // First argument is self
    };
    name: []const u8,
    type: Types,
};

fn GetType(definition: type, name: []const u8) type {
    if (@hasDecl(definition, name) or @hasField(definition, name)) {
        return @TypeOf(@field(definition, name));
    }
    return void;
}

fn getDeclaration(definition: type, comptime name: []const u8) ?GetType(definition, name) {
    if (@hasDecl(definition, name)) {
        return @field(definition, name);
    }
    return null;
}

fn Error(comptime fmt: []const u8, comptime args: anytype, comptime e: err) !void {
    comptime {
        if (!builtin.is_test) {
            @compileError(std.fmt.comptimePrint(fmt, args));
        } else {
            return e;
        }
    }
}

fn inStrArray(array: [][]const u8, value: []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, item, value)) {
            return true;
        }
    }
    return false;
}

fn inDeclArray(array: []const std.builtin.Type.Declaration, value: []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, item.name, value)) {
            return true;
        }
    }
    return false;
}

const err = error{
    MissingRequiredField,
    InvalidRootModule,
    UnknownDeclaration,
};

pub fn traverse(definition: type, comptime name: []const u8, comptime is_root: bool) !Container {
    comptime {
        const type_info = @typeInfo(definition);

        if (is_root) {
            if (type_info != .Struct) {
                return Error(
                    "Root module {s} must be a struct",
                    .{name},
                    err.InvalidRootModule,
                );
            }
            const typeDecl = getDeclaration(definition, "Type") orelse {
                return Error(
                    "Root module {s} is missing required declaration: Type",
                    .{name},
                    err.MissingRequiredField,
                );
            };

            if (typeDecl != .Module) {
                return Error(
                    "Root module {s} must be of type Module",
                    .{name},
                    err.InvalidRootModule,
                );
            }
        }

        switch (type_info) {
            .Struct => |data| {
                var container = std.mem.zeroes(Container);
                container.name = name;

                var handled_declarations: [data.decls.len][]const u8 = .{""} ** data.decls.len;
                var handled_index = 0;

                var declarations: []const Declaration = &[_]Declaration{};
                var sub_containers: []const Container = &[_]Container{};
                var fns: []const Fn = &[_]Fn{};

                for (Declaration.all_special_decls) |special_decl| {
                    if (!inDeclArray(data.decls, @tagName(special_decl))) {
                        continue;
                    }

                    const decl = getDeclaration(definition, @tagName(special_decl)) orelse {
                        if (special_decl.isRequired()) {
                            return Error(
                                "Struct {s} is missing required declaration: {s}",
                                .{ name, @tagName(special_decl) },
                                err.MissingRequiredField,
                            );
                        }
                        continue;
                    };

                    // TODO: Match Types Otherwise Error
                    if (special_decl.isPyZi()) {
                        @field(container, special_decl.fieldNamePyZi()) = decl;
                        handled_declarations[handled_index] = @tagName(special_decl);
                        handled_index += 1;
                    } else {
                        declarations = declarations ++ .{
                            Declaration{
                                .type = .{ .Special = special_decl },
                                .name = @tagName(special_decl),
                            },
                        };

                        handled_declarations[handled_index] = @tagName(special_decl);
                        handled_index += 1;
                    }
                }

                for (data.decls) |decl| {
                    // Skip declarations that have been handled
                    if (inStrArray(&handled_declarations, decl.name)) {
                        continue;
                    }

                    handled_declarations[handled_index] = decl.name;
                    handled_index += 1;

                    const decl_type_info = @typeInfo(@TypeOf(@field(definition, decl.name)));
                    const is_const = @typeInfo(@TypeOf(&@field(definition, decl.name))).Pointer.is_const;

                    if (decl_type_info != .Type and decl_type_info != .Fn) {
                        // Can only be a class attribute
                        declarations = declarations ++ .{
                            Declaration{
                                .type = .{ .ClassAttribute = if (is_const) .Const else .Var },
                                .name = decl.name,
                            },
                        };
                        continue;
                    }

                    // Check if it is a Fn
                    if (decl_type_info == .Fn) {
                        // TODO: Fill out function information

                        const fn_type: Fn.Types = if (inStrArray(
                            @constCast(&Fn.all_special_names),
                            decl.name,
                        )) .Special else blk: {
                            if (decl_type_info.Fn.params.len < 1) break :blk .Static;
                            if (decl_type_info.Fn.params[0].type == *definition) {
                                break :blk .Class;
                            } else {
                                break :blk .Static;
                            }
                        };

                        fns = fns ++ .{.{
                            .name = decl.name,
                            .type = fn_type,
                        }};
                        continue;
                    }

                    const decl_info = @typeInfo(@field(definition, decl.name));
                    if (decl_info == .Struct) {
                        sub_containers = sub_containers ++ .{
                            try traverse(
                                @field(definition, decl.name),
                                decl.name,
                                false,
                            ),
                        };
                        continue;
                    }

                    try Error(
                        "Unknown Declaration: {s} of type {any}",
                        .{ decl.name, decl_info },
                        err.UnknownDeclaration,
                    );
                }

                container.decls = declarations;
                container.sub_containers = sub_containers;
                container.fns = fns;

                return container;
            },
            else => unreachable,
        }
    }
}

test "Test Basic Root Module" {
    const root = struct {
        pub const Type: Container.Type = .Module;
    };

    comptime {
        _ = try traverse(
            root,
            "Root",
            true,
        );
    }
}

test "Test Basic Root Without Type" {
    const root = struct {
        pub const Typ: Container.Type = .Module;
    };

    comptime {
        try std.testing.expectError(err.MissingRequiredField, traverse(
            root,
            "Root",
            true,
        ));
    }
}
test "Test Basic Root With Wrong Type" {
    const root = struct {
        pub const Type: Container.Type = .Class;
    };

    comptime {
        try std.testing.expectError(err.InvalidRootModule, traverse(
            root,
            "Root",
            true,
        ));
    }
}

test "Test Basic Root Other Declarations" {
    const root = struct {
        pub const Type: Container.Type = .Module;
        pub const PhaseType: Container.PhaseType = .MultiPhase;
        pub const a: u32 = 1;
        pub var b: u32 = 2;
        pub const doc =
            \\ Cringe Root Module
            \\ Cringe Root Module
            \\ Cringe Root Module
        ;
    };

    comptime {
        var expected = std.mem.zeroes(Container);
        expected.type = .Module;
        expected.phase_type = .MultiPhase;
        expected.name = "Root";

        expected.decls = &[_]Declaration{ .{
            .type = .{ .Special = .doc },
            .name = "doc",
        }, .{
            .type = .{ .ClassAttribute = .Const },
            .name = "a",
        }, .{
            .type = .{ .ClassAttribute = .Var },
            .name = "b",
        } };

        const val = try traverse(
            root,
            "Root",
            true,
        );
        try std.testing.expectEqualDeep(expected, val);
    }
}

test "Test Basic Root With Sub Modules" {
    const root = struct {
        pub const Type: Container.Type = .Module;
        pub const Sub = struct {
            pub const Type: Container.Type = .Class;
        };
    };

    comptime {
        var expected = std.mem.zeroes(Container);
        expected.type = .Module;
        expected.name = "Root";

        var sub = std.mem.zeroes(Container);
        sub.type = .Class;
        sub.name = "Sub";

        expected.sub_containers = &[_]Container{sub};

        const val = try traverse(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
test "Test Basic Root With Functions" {
    const root = struct {
        pub const Type: Container.Type = .Module;

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
        var expected = std.mem.zeroes(Container);
        expected.type = .Module;
        expected.name = "Root";
        expected.fns = &[_]Fn{
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

        const val = try traverse(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
test "Test Nested Module With Delarations and Functions" {
    // const root = struct {
    //     pub const Type: Container.Type = .Module;
    //     pub const Sub = struct {
    //         pub const Type: Container.Type = .Class;
    //     };
    // };
    //
    // comptime {
    //     var expected = std.mem.zeroes(Container);
    //     expected.type = .Module;
    //     expected.name = "Root";
    //     expected.sub_containers =
    //
    //     const val = try traverse(
    //         root,
    //         "Root",
    //         true,
    //     );
    //
    //     try std.testing.expectEqualDeep(expected, val);
    // }
}
