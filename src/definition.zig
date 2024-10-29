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

    const Types = union(enum) {
        ZigOnly, // Not public are always zig only
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

fn Error(comptime fmt: []const u8, args: anytype, e: anytype) !void {
    if (!builtin.is_test) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else {
        return e;
    }
}

fn inArray(array: [][]const u8, value: []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, item, value)) {
            return true;
        }
    }
    return false;
}

const err = error{
    MissingRequiredField,
    InvalidRootModule,
};

pub fn traverse(definition: type, name: []const u8, is_root: bool) !Container {
    const type_info = @typeInfo(definition);

    @setEvalBranchQuota(std.math.maxInt(u32));

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

            for (Declaration.all_special_decls) |special_decl| {
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
                if (inArray(&handled_declarations, decl.name)) {
                    continue;
                }

                handled_declarations[handled_index] = decl.name;
                handled_index += 1;

                const decl_info = @typeInfo(GetType(definition, decl.name));
                const is_const = @typeInfo(@TypeOf(&@field(definition, decl.name))).Pointer.is_const;
                if (!is_const) {
                    // Can only be a class attribute
                    declarations = declarations ++ .{
                        Declaration{
                            .type = .{ .ClassAttribute = .Var },
                            .name = decl.name,
                        },
                    };
                    continue;
                }

                // @compileLog(decl_info);
                if (decl_info == .Struct) {
                    sub_containers = sub_containers ++ .{traverse(
                        @TypeOf(@field(definition, decl.name)),
                        decl.name,
                        false,
                    )};
                }

                // Check if it is a Fn

                // Must be a constant class attribute
                declarations = declarations ++ .{
                    Declaration{
                        .type = .{ .ClassAttribute = .Const },
                        .name = decl.name,
                    },
                };
            }

            container.decls = declarations;

            return container;
        },
        else => unreachable,
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
