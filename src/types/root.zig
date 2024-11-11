const std = @import("std");
const def = @import("../tokenize/definitions.zig");
const tok = @import("../tokenize/tokenizer.zig");
const config = @import("config");
const c = @import("../c.zig");
const common = @import("../common.zig");

// TODO: Implement all the special module functions and types

// m_base: Done
// m_name: Done,
// m_doc: Done,
// m_size: Done,
// m_methods: .{
//      ml_name: Can_Be_Handled,
//      ml_meth: Needs_To_Be_Defined = Conversion from zig function to the needed function signature,
//      ml_flags: Can_Be_Handled - Only for overridden functions,
//      ml_doc: Can_Be_Handled,
// },
// m_slots: .{
//      slot: Needs_To_Be_Defined,
//      value: Needs_To_Be_Defined,
// },
// m_traverse: Can_Be_Handled,
// m_clear: Can_Be_Handled,
// m_free: Can_Be_Handled,

const Error = error{
    IncompatibleSpecialDeclaration,
    IncompatibleFunctionDeclaration,
};

fn defineSinglePhasedModuleType(module: def.Container) !void {
    var module_def: c.PyModuleDef = .{
        .m_base = .{
            .ob_base = .{
                .unnamed_0 = .{ .ob_refcnt = 1 },
                .ob_type = null,
            },
            .m_init = null,
            .m_index = 0,
            .m_copy = null,
        },
        .m_name = module.name.ptr,
        .m_size = -1,
    };

    // Handles all the special declarations
    for (module.decls) |decl| {
        switch (decl.type) {
            .Special => |data| {
                switch (data) {
                    .doc,
                    .size,
                    => @field(module_def, "m_" ++ @tagName(data)) = @field(module.definition, decl.name),
                    .create,
                    .exec,
                    => return common.Error(
                        "Function {} can only be defined in a Multi-Phased Module",
                        .{@tagName(data)},
                        error.IncompatibleSpecialDeclaration,
                    ),
                    .fn_flags,
                    .fn_doc,
                    .Type,
                    .PhaseType,
                    => continue,
                }
            },
            else => continue,
        }
    }

    // Handles all the functions
    for (module.fns) |function| {
        switch (function.type) {
            .Class => return common.Error(
                "Class Functions cannot be defined in a Module",
                .{},
                error.IncompatibleFunctionDeclaration,
            ),
            .Special => {},
            .Static => {},
            .Overridden => {},
        }
    }

    @compileLog(module_def);
}

test "Dirty Testing" {
    const root = struct {
        pub const Type = def.Container.Type.Module;
        pub const doc = "This is a test module";
    };

    comptime {
        const tokens = try tok.tokenize(
            root,
            config.module_name,
            true,
        );

        try defineSinglePhasedModuleType(tokens);
    }
}

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
