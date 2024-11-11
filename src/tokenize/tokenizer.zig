const std = @import("std");
const builtin = @import("builtin");
const def = @import("definitions.zig");
const common = @import("../common.zig");

fn matchesWildcard(array: [][]const u8, value: []const u8) ?u32 {
    for (array) |item| {
        if (value.len <= item.len) {
            continue;
        }

        if (std.mem.eql(u8, item, value[0..item.len])) {
            return item.len;
        }
    }
    return null;
}

pub const Errors = error{
    MissingRequiredField,
    InvalidRootModule,
    UnknownDeclaration,
    TypeMismatch,
};

fn isValidRootModule(definition: type, name: []const u8) !void {
    const type_info = @typeInfo(definition);
    if (type_info != .Struct) {
        return common.Error(
            "Root module {s} must be a struct",
            .{name},
            Errors.InvalidRootModule,
        );
    }

    if (!@hasDecl(definition, "Type")) {
        return common.Error(
            "Root module {s} is missing required declaration: Type",
            .{name},
            Errors.MissingRequiredField,
        );
    }

    const isValid: def.Container.Type = @field(definition, "Type");
    _ = isValid;

    if (@field(definition, "Type") != .Module) {
        return common.Error(
            "Root module {s} must be of type Module",
            .{name},
            Errors.InvalidRootModule,
        );
    }
}

fn isAnonStruct(name: []const u8) bool {
    var last_dot: usize = 0;

    for (name, 0..) |c, i| {
        if (c == '.') {
            last_dot = i;
        }
    }
    const last_str = name[last_dot..];

    var first_underscore: ?usize = null;
    var last_underscore: usize = last_str.len;

    for (last_str, 0..) |c, i| {
        if (c == '_') {
            if (first_underscore == null) {
                first_underscore = i;
            }
            last_underscore = i;
        }
    }

    // Never found an underscore
    if (first_underscore == null) {
        return false;
    }

    // Check if the string has __struct_ between the first and last underscore
    if (!std.mem.eql(u8, last_str[first_underscore.? .. last_underscore + 1], "__struct_")) {
        return false;
    }

    // Check if all values after the last underscore are numbers
    for (last_str[last_underscore + 1 ..]) |c| {
        if (c < '0' or c > '9') {
            return false;
        }
    }

    return true;
}

fn handleDeclaration(definition: type, decl: std.builtin.Type.Declaration) !union(enum) {
    PyZiDeclaration: def.Declaration.SpecialDecls,
    Declaration: def.Declaration,
    Fn: def.Fn,
    Container: def.Container,
} {
    const decl_type_info = @typeInfo(@TypeOf(@field(definition, decl.name)));
    if (decl_type_info != .Type and decl_type_info != .Fn) {
        // If it is a special declaration
        if (common.inStrArray(@constCast(&def.Declaration.all_special_decls), decl.name)) {

            // TODO: Check for types
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
                        .definition = @TypeOf(@field(definition, @tagName(special_decl))),
                    },
                };
            }
        }

        const wildcard = matchesWildcard(@constCast(&def.Declaration.wildcard_decls), decl.name);
        if (wildcard != null) {
            return .{
                .Declaration = def.Declaration{
                    .type = .{
                        .Special = @field(def.Declaration.SpecialDecls, decl.name[0 .. wildcard.? - 1]),
                    },
                    .name = decl.name[wildcard.?..],
                    .definition = @TypeOf(@field(definition, decl.name)),
                },
            };
        }

        // Can only be a class attribute
        const is_const = @typeInfo(@TypeOf(&@field(definition, decl.name))).Pointer.is_const;
        return .{
            .Declaration = def.Declaration{
                .type = .{ .ClassAttribute = if (is_const) .Const else .Var },
                .name = decl.name,
                .definition = @TypeOf(@field(definition, decl.name)),
            },
        };
    }

    // Check if it is a Fn
    if (decl_type_info == .Fn) {
        // TODO: Fill out function information
        // TODO: Overridden functions
        const fn_type: def.Fn.Types = if (common.inStrArray(@constCast(&def.Fn.all_special_names), decl.name)) blk: {
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
                .definition = @TypeOf(@field(definition, decl.name)),
            },
        };
    }

    const decl_info = @typeInfo(@field(definition, decl.name));
    if (decl_info == .Struct) {
        return .{
            .Container = try tokenize(
                @field(definition, decl.name),
                decl.name,
                false,
            ),
        };
    }

    return common.Error(
        "Unknown Declaration: {s} of type {any}",
        .{ decl.name, decl_info },
        Errors.UnknownDeclaration,
    );
}

fn handleField(field: std.builtin.Type.StructField) def.Field {
    if (isAnonStruct(@typeName(field.type))) {
        if (@hasDecl(field.type, "get") or @hasDecl(field.type, "set")) {
            return .{
                .name = field.name,
                .type = .{
                    .Property = .{
                        .get = @hasDecl(field.type, "get"),
                        .set = @hasDecl(field.type, "set"),
                    },
                },
                .definition = field.type,
            };
        } else {
            return .{
                .name = field.name,
                .type = .InstanceAttribute,
                .definition = field.type,
            };
        }
    } else {
        return .{
            .name = field.name,
            .type = .Normal,
            .definition = field.type,
        };
    }
}

pub fn tokenize(definition: type, name: []const u8, is_root: bool) Errors!def.Container {
    comptime {
        if (is_root) try isValidRootModule(definition, name);
        const type_info = @typeInfo(definition);

        if (type_info != .Struct) {
            return common.Error(
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
            .definition = definition,
        };

        var all_declarations: [data.decls.len][]const u8 = .{""} ** data.decls.len;
        for (0..data.decls.len) |i| {
            all_declarations[i] = data.decls[i].name;
        }

        // Check if Required Declarations are present
        for (def.Declaration.required_decls) |required| {
            if (!common.inStrArray(&all_declarations, required)) {
                return common.Error(
                    "Struct {s} is missing required declaration: {s}",
                    .{ name, required },
                    Errors.MissingRequiredField,
                );
            }
        }

        // Handle Declarations
        for (data.decls) |decl| {
            switch (try handleDeclaration(definition, decl)) {
                .Declaration => |res| container.decls = container.decls ++ .{res},
                .Fn => |res| container.fns = container.fns ++ .{res},
                .Container => |res| container.subs = container.subs ++ .{res},
                .PyZiDeclaration => |res| @field(
                    container,
                    res.fieldNamePyZi(),
                ) = @field(
                    definition,
                    decl.name,
                ),
            }
        }

        // Handle Fields
        for (data.fields) |field| {
            container.fields = container.fields ++ .{handleField(field)};
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
        pub const fn_doc_a: []const u8 =
            \\ Cringe Function
            \\ Cringe Function
            \\ Cringe Function
        ;
        pub const fn_doc_: []const u8 =
            \\ Cringe Function
            \\ Cringe Function
            \\ Cringe Function
        ;
        pub const doc: []const u8 =
            \\ Cringe Root Module
            \\ Cringe Root Module
            \\ Cringe Root Module
        ;
    };

    comptime {
        const expected: def.Container = .{
            .type = .Module,
            .phase_type = .MultiPhase,
            .name = "Root",
            .decls = &[_]def.Declaration{
                .{
                    .type = .{ .ClassAttribute = .Const },
                    .name = "a",
                    .definition = u32,
                },
                .{
                    .type = .{ .ClassAttribute = .Var },
                    .name = "b",
                    .definition = u32,
                },
                .{
                    .type = .{ .Special = .fn_doc },
                    .name = "a",
                    .definition = []const u8,
                },
                .{
                    .type = .{ .ClassAttribute = .Const },
                    .name = "fn_doc_",
                    .definition = []const u8,
                },
                .{
                    .type = .{ .Special = .doc },
                    .name = "doc",
                    .definition = []const u8,
                },
            },
            .subs = &[_]def.Container{},
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{},
            .definition = root,
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
        const expected: def.Container = .{
            .type = .Module,
            .name = "Root",
            .subs = &[_]def.Container{
                .{
                    .type = .Class,
                    .name = "Sub",
                    .subs = &[_]def.Container{},
                    .fns = &[_]def.Fn{},
                    .fields = &[_]def.Field{},
                    .definition = root.Sub,
                    .decls = &[_]def.Declaration{},
                },
            },
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{},
            .definition = root,
            .decls = &[_]def.Declaration{},
        };

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
        const expected: def.Container = .{
            .type = .Module,
            .name = "Root",
            .subs = &[_]def.Container{},
            .fns = &[_]def.Fn{
                .{
                    .name = "init",
                    .type = .Special,
                    .definition = fn () void,
                },
                .{
                    .name = "cringe",
                    .type = .Class,
                    .definition = fn (_: *root) void,
                },
                .{
                    .name = "dumb",
                    .type = .Static,
                    .definition = fn () void,
                },
                .{
                    .name = "dumb1",
                    .type = .Static,
                    .definition = fn (_: u32) void,
                },
                .{
                    .name = "dumb2",
                    .type = .Static,
                    .definition = fn (_: u32, _: i32) void,
                },
            },
            .fields = &[_]def.Field{},
            .definition = root,
            .decls = &[_]def.Declaration{},
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
            pub const doc: []const u8 =
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
        const expected: def.Container = .{
            .type = .Module,
            .name = "Root",
            .subs = &[_]def.Container{
                .{
                    .type = .Module,
                    .phase_type = .MultiPhase,
                    .name = "Sub",
                    .subs = &[_]def.Container{},
                    .fns = &[_]def.Fn{
                        .{
                            .name = "init",
                            .type = .Special,
                            .definition = fn () void,
                        },
                        .{
                            .name = "cringe",
                            .type = .Class,
                            .definition = fn (_: *root.Sub) void,
                        },
                        .{
                            .name = "dumb",
                            .type = .Static,
                            .definition = fn () void,
                        },
                        .{
                            .name = "dumb1",
                            .type = .Static,
                            .definition = fn (_: u32) void,
                        },
                        .{
                            .name = "dumb2",
                            .type = .Static,
                            .definition = fn (_: u32, _: i32) void,
                        },
                    },
                    .fields = &[_]def.Field{},
                    .definition = root.Sub,
                    .decls = &[_]def.Declaration{
                        .{
                            .type = .{ .ClassAttribute = .Const },
                            .name = "a",
                            .definition = u32,
                        },
                        .{
                            .type = .{ .ClassAttribute = .Var },
                            .name = "b",
                            .definition = u32,
                        },
                        .{
                            .type = .{ .Special = .doc },
                            .name = "doc",
                            .definition = []const u8,
                        },
                    },
                },
            },
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{},
            .definition = root,
            .decls = &[_]def.Declaration{},
        };

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}

test "Test isAnonStruct Function" {
    try std.testing.expectEqual(true, isAnonStruct("new.abc__struct_897"));
    try std.testing.expectEqual(true, isAnonStruct("new.abc.cde__struct_821123"));
    try std.testing.expectEqual(true, isAnonStruct("cde__struct_821123"));

    try std.testing.expectEqual(false, isAnonStruct("new.abc.cde__struct_821123.hello"));
    try std.testing.expectEqual(false, isAnonStruct("new.abc.cde__struct_12c"));
    try std.testing.expectEqual(false, isAnonStruct("hello.world"));
    try std.testing.expectEqual(false, isAnonStruct("hello"));
    try std.testing.expectEqual(false, isAnonStruct("hello.new(.{})"));
}
test "Test Basic Fields" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;

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

    comptime {
        const val = try tokenize(
            root,
            "Root",
            true,
        );

        const r: root = .{
            .a = 1,
            .b = .{ .val = 2 },
            .c = .{ .val = 3 },
            .d = .{ .val = 4 },
            .e = .{ .val = 5 },
        };

        const expected: def.Container = .{
            .type = .Module,
            .name = "Root",
            .subs = &[_]def.Container{},
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{
                .{
                    .name = "a",
                    .type = .Normal,
                    .definition = u32,
                },
                .{
                    .name = "b",
                    .type = .InstanceAttribute,
                    .definition = @TypeOf(r.b),
                },
                .{
                    .name = "c",
                    .type = .{ .Property = .{
                        .get = true,
                        .set = false,
                    } },
                    .definition = @TypeOf(r.c),
                },
                .{
                    .name = "d",
                    .type = .{ .Property = .{
                        .get = false,
                        .set = true,
                    } },
                    .definition = @TypeOf(r.d),
                },
                .{
                    .name = "e",
                    .type = .{ .Property = .{
                        .get = true,
                        .set = true,
                    } },
                    .definition = @TypeOf(r.e),
                },
            },
            .definition = root,
            .decls = &[_]def.Declaration{},
        };

        try std.testing.expectEqualDeep(expected, val);
    }
}

test "Full Module" {
    const root = struct {
        pub const Type: def.Container.Type = .Module;
        pub const Sub1 = struct {
            pub const Type: def.Container.Type = .Module;
            pub const PhaseType: def.Container.PhaseType = .MultiPhase;
            pub const a: u32 = 1;
            pub var b: u32 = 2;
            pub const doc: []const u8 =
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

    comptime {
        const r: root.Sub2 = .{
            .a = 1,
            .b = .{ .val = 2 },
            .c = .{ .val = 3 },
            .d = .{ .val = 4 },
            .e = .{ .val = 5 },
        };
        const expected: def.Container = .{
            .type = .Module,
            .name = "Root",
            .subs = &[_]def.Container{
                .{
                    .type = .Module,
                    .phase_type = .MultiPhase,
                    .name = "Sub1",
                    .subs = &[_]def.Container{},
                    .fns = &[_]def.Fn{
                        .{
                            .name = "init",
                            .type = .Special,
                            .definition = fn () void,
                        },
                        .{
                            .name = "cringe",
                            .type = .Class,
                            .definition = fn (_: *root.Sub1) void,
                        },
                        .{
                            .name = "dumb",
                            .type = .Static,
                            .definition = fn () void,
                        },
                        .{
                            .name = "dumb1",
                            .type = .Static,
                            .definition = fn (_: u32) void,
                        },
                        .{
                            .name = "dumb2",
                            .type = .Static,
                            .definition = fn (_: u32, _: i32) void,
                        },
                    },
                    .fields = &[_]def.Field{},
                    .definition = root.Sub1,
                    .decls = &[_]def.Declaration{
                        .{
                            .type = .{ .ClassAttribute = .Const },
                            .name = "a",
                            .definition = u32,
                        },
                        .{
                            .type = .{ .ClassAttribute = .Var },
                            .name = "b",
                            .definition = u32,
                        },
                        .{
                            .type = .{ .Special = .doc },
                            .name = "doc",
                            .definition = []const u8,
                        },
                    },
                },
                .{
                    .type = .Class,
                    .name = "Sub2",
                    .subs = &[_]def.Container{},
                    .fns = &[_]def.Fn{},
                    .fields = &[_]def.Field{
                        .{
                            .name = "a",
                            .type = .Normal,
                            .definition = u32,
                        },
                        .{
                            .name = "b",
                            .type = .InstanceAttribute,
                            .definition = @TypeOf(r.b),
                        },
                        .{
                            .name = "c",
                            .type = .{ .Property = .{
                                .get = true,
                                .set = false,
                            } },
                            .definition = @TypeOf(r.c),
                        },
                        .{
                            .name = "d",
                            .type = .{ .Property = .{
                                .get = false,
                                .set = true,
                            } },
                            .definition = @TypeOf(r.d),
                        },
                        .{
                            .name = "e",
                            .type = .{ .Property = .{
                                .get = true,
                                .set = true,
                            } },
                            .definition = @TypeOf(r.e),
                        },
                    },
                    .definition = root.Sub2,
                    .decls = &[_]def.Declaration{},
                },
            },
            .fns = &[_]def.Fn{},
            .fields = &[_]def.Field{},
            .definition = root,
            .decls = &[_]def.Declaration{},
        };

        const val = try tokenize(
            root,
            "Root",
            true,
        );

        try std.testing.expectEqualDeep(expected, val);
    }
}
