// TODO: Better formatting for these classes
pub const Container = struct {
    pub const PhaseType = enum {
        SinglePhase, // Default
        MultiPhase,
    };

    pub const Type = enum {
        Module,
        Class, // TODO: Check if classes can be in multi-phase
    };

    type: Type,

    phase_type: PhaseType = .SinglePhase,
    name: []const u8,

    decls: []const Declaration,
    subs: []const @This(),
    fns: []const Fn,

    fields: []const Field,
};

pub const Declaration = struct {
    pub const SpecialDecls = enum {
        // Module Declarations
        doc,
        size,
        traverse,
        clear,
        free,
        // Multi-phase Declarations
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

    pub const Types = union(enum) {
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
    };
    type: Types,
    name: []const u8,
};

pub const Fn = struct {
    const SpecialFns = enum {
        init,
        lhs, // Research all special functions

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

    pub const Types = union(enum) {
        Special, // Has special name
        Static, // No self
        Class, // First argument is self
    };
    name: []const u8,
    type: Types,
};
