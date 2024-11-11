const std = @import("std");
const spacing = "    ";

pub const Container = struct {
    pub const PhaseType = enum {
        SinglePhase, // Default
        MultiPhase,
    };

    pub const Type = enum {
        Module,
        Class, // TODO: Check if classes can be in multi-phase
    };

    name: []const u8,
    type: Type,
    phase_type: PhaseType = .SinglePhase,
    decls: []const Declaration,
    fns: []const Fn,
    fields: []const Field,
    subs: []const @This(),
    definition: type,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        const initial_tabs = options.width orelse 0;
        const tab = spacing ** (initial_tabs);
        const tab1 = spacing ** (initial_tabs + 1);
        const tab2 = spacing ** (initial_tabs + 2);

        const f = std.fmt.comptimePrint(
            "\n{{s}}{{:{}}},",
            .{
                initial_tabs + 2,
            },
        );

        const f1 =
            \\Container{{
            \\{s}name = "{s}",
            \\{s}type = .{s},
            \\{s}phase_type = .{s},
            \\{s}declarations = .{{
        ;
        _ = try writer.print(f1, .{
            tab1,
            self.name,
            tab1,
            @tagName(self.type),
            tab1,
            @tagName(self.phase_type),
            tab1,
        });

        for (self.decls) |decl| {
            _ = try writer.print(f, .{ tab2, decl });
        }

        const f2 = if (self.decls.len > 0)
            \\
            \\{s}}},
            \\{s}fns = .{{
        else
            \\}},{s}
            \\{s}functions = .{{
            ;
        _ = try writer.print(f2, .{ tab1, tab1 });

        for (self.fns) |func| {
            _ = try writer.print(f, .{ tab2, func });
        }

        const f3 = if (self.fns.len > 0)
            \\
            \\{s}}},
            \\{s}fields = .{{
        else
            \\}},{s}
            \\{s}fields = .{{
            ;

        _ = try writer.print(f3, .{ tab1, tab1 });

        for (self.fields) |field| {
            _ = try writer.print(f, .{ tab2, field });
        }

        const f4 = if (self.fields.len > 0)
            \\
            \\{s}}},
            \\{s}sub_containers = .{{
        else
            \\}},{s}
            \\{s}sub_containers = .{{
            ;

        _ = try writer.print(f4, .{ tab1, tab1 });

        for (self.subs) |sub| {
            _ = try writer.print(f, .{ tab2, sub });
        }

        const f5 = if (self.subs.len > 0)
            \\
            \\{s}}},
            \\{s}}}
        else
            \\}},{s}
            \\{s}}}
            ;
        _ = try writer.print(f5, .{ tab1, tab });
    }
};

pub const Declaration = struct {
    pub const SpecialDecls = enum {
        // Module Declarations
        doc,
        size,
        // Module Method Declarations
        fn_flags,
        fn_doc,
        // Multi-phase Module Declarations
        create,
        exec,
        // PyZi Declarations
        Type,
        PhaseType,

        pub fn isPyZi(self: *const @This()) bool {
            switch (self.*) {
                .Type,
                .PhaseType,
                => return true,
                else => return false,
            }
        }

        pub fn isPython(self: *const @This()) bool {
            return !self.isPyZi();
        }

        pub fn isRequired(self: *const @This()) bool {
            switch (self.*) {
                .Type => return true,
                else => return false,
            }
        }

        pub fn isWildcard(self: *const @This()) bool {
            switch (self.*) {
                .fn_flags,
                .fn_doc,
                => return true,

                else => return false,
            }
        }

        pub fn fieldNamePyZi(self: *const @This()) []const u8 {
            switch (self.*) {
                .Type => return "type",
                .PhaseType => return "phase_type",
                else => unreachable,
            }
        }

        pub fn GetType(self: *const @This()) type {
            switch (self.*) {
                .Type => return Container.Type,
                .PhaseType => return Container.PhaseType,
                else => unreachable,
            }
        }
    };

    pub const all_special_decls = blk: {
        const len = @typeInfo(SpecialDecls).Enum.fields.len;
        var fields: [len][]const u8 = .{""} ** len;

        for (0..len) |i| {
            fields[i] = @tagName(@as(SpecialDecls, @enumFromInt(i)));
        }

        break :blk fields;
    };

    pub const required_decls = blk: {
        const len = @typeInfo(SpecialDecls).Enum.fields.len;
        var required = 0;

        for (0..len) |i| {
            const field: SpecialDecls = @enumFromInt(i);
            if (field.isRequired()) {
                required += 1;
            }
        }
        var fields: [required][]const u8 = .{""} ** required;

        for (0..len) |i| {
            const field: SpecialDecls = @enumFromInt(i);
            if (field.isRequired()) {
                required -= 1;
                fields[required] = @tagName(field);
            }
        }

        break :blk fields;
    };

    pub const wildcard_decls = blk: {
        const len = @typeInfo(SpecialDecls).Enum.fields.len;
        var required = 0;

        for (0..len) |i| {
            const field: SpecialDecls = @enumFromInt(i);
            if (field.isWildcard()) {
                required += 1;
            }
        }
        var fields: [required][]const u8 = .{""} ** required;

        for (0..len) |i| {
            const field: SpecialDecls = @enumFromInt(i);
            if (field.isWildcard()) {
                required -= 1;
                fields[required] = @tagName(field) ++ "_";
            }
        }

        break :blk fields;
    };

    pub const Types = union(enum) {
        Special: SpecialDecls, // Special PyZi/Python Declarations: Has special name.
        // Class Attribute: Can be accessed in zig and python.
        // If not special and is public it is assumed to be class/module attribute/constant.
        ClassAttribute: enum(u1) {
            Const,
            Var,
        },
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .Special => |data| {
                    const f = "Special = {s}";
                    _ = try writer.print(f, .{@tagName(data)});
                },
                .ClassAttribute => |data| {
                    const f = "ClassAttribute = {s}";
                    _ = try writer.print(f, .{@tagName(data)});
                },
            }
        }
    };

    type: Types,
    name: []const u8,
    definition: type,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        const initial_tabs = options.width orelse 0;
        const tab = spacing ** (initial_tabs);
        const tab1 = spacing ** (initial_tabs + 1);

        const f =
            \\Declaration{{
            \\{s}name = "{s}",
            \\{s}type = .{},
            \\{s}}}
        ;

        _ = try writer.print(f, .{
            tab1,
            self.name,
            tab1,
            self.type,
            tab,
        });
    }
};

pub const Field = struct {
    pub const Types = union(enum) {
        // Can only be accessed in zig
        Normal,
        // Can find if anonymous if contains last split from decimal contains __struct_ in the name followed by numbers.
        // Example 1: new.abc__struct_897
        // Example 2: new.abc.cde__struct_821
        // If it is an anonymous struct with no functions and not registered it is a Instance Attribute.
        InstanceAttribute,
        // If a struct with property functions and not registered it is a Property.
        Property: struct {
            set: bool = false,
            get: bool = false,
        }, // Figure out what properties are
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .Property => |data| {
                    if (data.set and data.get) {
                        const f = "Property = gs";
                        _ = try writer.print(f, .{});
                    } else if (data.set) {
                        const f = "Property = s";
                        _ = try writer.print(f, .{});
                    } else if (data.get) {
                        const f = "Property = g";
                        _ = try writer.print(f, .{});
                    }
                },
                else => _ = try writer.print("{s}", .{@tagName(self)}),
            }
        }
    };
    type: Types,
    definition: type,
    name: []const u8,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        const initial_tabs = options.width orelse 0;
        const tab = spacing ** (initial_tabs);
        const tab1 = spacing ** (initial_tabs + 1);

        const f =
            \\Field{{
            \\{s}name = "{s}",
            \\{s}type = .{},
            \\{s}}}
        ;

        _ = try writer.print(f, .{
            tab1,
            self.name,
            tab1,
            self.type,
            tab,
        });
    }
};

pub const Fn = struct {
    const SpecialFns = enum {
        // Both
        init,

        // Module
        traverse,
        clear,
        free,

        // Class
        lhs,

        pub fn GetType(self: *const @This()) type {
            _ = self;
        }
    };

    pub const all_special_names = blk: {
        const len = @typeInfo(SpecialFns).Enum.fields.len;
        var fields: [len][]const u8 = .{""} ** len;

        for (0..len) |i| {
            fields[i] = @tagName(@as(SpecialFns, @enumFromInt(i)));
        }

        break :blk fields;
    };

    pub const Types = enum {
        Special, // Has special name
        Static, // No self
        Class, // First argument is self
        Overridden, // TODO: Overridden function.
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            _ = try writer.print("{s}", .{@tagName(self)});
        }
    };

    pub const Flags = packed struct(c_int) {
        VariableArguemnts: bool = false,
        KeywordArguements: bool = false,
        NoArguments: bool = false,
        OneArguement: bool = false,
        Class: bool = false,
        Static: bool = false,
        CoExist: bool = false,
        FastCall: bool = false,
        Stackless: bool = false,
        Method: bool = false,
        __unused: u22 = 0,

        fn isValidPermutation(self: *const @This()) bool {
            if (self.Stackless) {
                return false;
            }

            // METH_VARARGS
            if (self.VariableArguemnts and
                !self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                !self.FastCall and
                !self.Method) return true;

            // METH_KEYWORDS
            if (!self.VariableArguemnts and
                self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                !self.FastCall and
                !self.Method) return true;

            // METH_VARARGS | METH_KEYWORDS
            if (self.VariableArguemnts and
                self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                !self.FastCall and
                !self.Method) return true;

            // METH_FASTCALL
            if (!self.VariableArguemnts and
                !self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                self.FastCall and
                !self.Method) return true;

            // METH_FASTCALL | METH_KEYWORDS
            if (!self.VariableArguemnts and
                self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                self.FastCall and
                !self.Method) return true;

            // METH_METHOD
            if (!self.VariableArguemnts and
                !self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                !self.FastCall and
                self.Method) return true;

            // METH_METHOD | METH_FASTCALL | METH_KEYWORDS
            if (!self.VariableArguemnts and
                self.KeywordArguements and
                !self.NoArguments and
                !self.OneArguement and
                self.FastCall and
                self.Method) return true;

            // METH_NOARGS
            if (!self.VariableArguemnts and
                !self.KeywordArguements and
                self.NoArguments and
                !self.OneArguement and
                !self.FastCall and
                !self.Method) return true;

            // METH_O
            if (!self.VariableArguemnts and
                !self.KeywordArguements and
                !self.NoArguments and
                self.OneArguement and
                !self.FastCall and
                !self.Method) return true;

            return false;
        }

        fn signature(self: *const @This()) type {
            _ = self;
        }
    };

    name: []const u8,
    type: Types,
    definition: type,
    flags: Flags,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        const initial_tabs = options.width orelse 0;
        const tab = spacing ** (initial_tabs);
        const tab1 = spacing ** (initial_tabs + 1);

        const f =
            \\Function{{
            \\{s}name = "{s}",
            \\{s}type = .{},
            \\{s}}}
        ;

        _ = try writer.print(f, .{
            tab1,
            self.name,
            tab1,
            self.type,
            tab,
        });
    }
};

test "Flags Dirty" {
    const METH_VARARGS = @as(c_int, 0x0001);
    const METH_KEYWORDS = @as(c_int, 0x0002);
    const METH_NOARGS = @as(c_int, 0x0004);
    const METH_O = @as(c_int, 0x0008);
    const METH_CLASS = @as(c_int, 0x0010);
    const METH_STATIC = @as(c_int, 0x0020);
    const METH_COEXIST = @as(c_int, 0x0040);
    const METH_FASTCALL = @as(c_int, 0x0080);
    const METH_STACKLESS = @as(c_int, 0x0000);
    const METH_METHOD = @as(c_int, 0x0200);

    const f1: c_int = @bitCast(Fn.Flags{ .VariableArguemnts = true });
    try std.testing.expectEqual(f1, METH_VARARGS);

    const f2: c_int = @bitCast(Fn.Flags{ .KeywordArguements = true });
    try std.testing.expectEqual(f2, METH_KEYWORDS);

    const f3: c_int = @bitCast(Fn.Flags{ .NoArguments = true });
    try std.testing.expectEqual(f3, METH_NOARGS);

    const f4: c_int = @bitCast(Fn.Flags{ .OneArguement = true });
    try std.testing.expectEqual(f4, METH_O);

    const f5: c_int = @bitCast(Fn.Flags{ .Class = true });
    try std.testing.expectEqual(f5, METH_CLASS);

    const f6: c_int = @bitCast(Fn.Flags{ .Static = true });
    try std.testing.expectEqual(f6, METH_STATIC);

    const f7: c_int = @bitCast(Fn.Flags{ .CoExist = true });
    try std.testing.expectEqual(f7, METH_COEXIST);

    const f8: c_int = @bitCast(Fn.Flags{ .FastCall = true });
    try std.testing.expectEqual(f8, METH_FASTCALL);

    const f9: c_int = @bitCast(Fn.Flags{ .Stackless = true });
    try std.testing.expectEqual(f9, METH_STACKLESS);

    const f10: c_int = @bitCast(Fn.Flags{ .Method = true });
    try std.testing.expectEqual(f10, METH_METHOD);

    const f = Fn.Flags{ .Stackless = true };
    _ = f.isValidPermutation();
}
