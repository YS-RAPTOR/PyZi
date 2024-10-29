const c = @import("c.zig");
const std = @import("std");

// TODO: Convert definition into a comptime tree structure,
// All Relavent information needs to be stored

// TODO: Comptime define the structure of the module

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

// Consider converting this to a template function
const SinglePhaseModule = struct {

    // FIELDS NEEDED TO BE INITIALIZED
    // m_base - always the same
    // m_name - done
    // m_doc - done
    // m_size

    // m_methods
    // m_slots

    fn init(name: []const u8, definition: type) !@This() {
        const doc = getDeclaration(definition, "doc");

        // TODO: Think about function arguements and how that could be changed
        const traverse = getDeclaration(definition, "traverse");

        // TODO: Maybe have orelses for these functions
        const clear = getDeclaration(definition, "clear");
        const free = getDeclaration(definition, "free");

        // TODO: Provide a helper function to get the size of the type automatically for given definition.
        // Maybe also include way to ignore fields.
        const size = getDeclaration(definition, "size") orelse -1;

        _ = name;
        _ = doc;
        _ = traverse;
        _ = clear;

        return .{};
    }
};

// TODO: Multi-Phase Module
const MultiPhaseModule = struct {
    fn init(name: []const u8, definition: type) !@This() {
        const doc = getDeclaration(definition, "doc");
        _ = name;
        _ = doc;
        return .{};
    }
};

// TODO: Any reason to make this a union?
const Module = union {
    single: SinglePhaseModule,
    multi: MultiPhaseModule,

    const Options = struct {
        name: []const u8 = @import("config").module_name,
        no_of_phases: enum { single, multi } = .single,
    };

    pub inline fn init(definition: type, options: Options) !@This() {
        switch (options.no_of_phases) {
            .single => return .{ .single = try SinglePhaseModule.init(
                options.name,
                definition,
            ) },
            .multi => return .{
                .multi = try MultiPhaseModule.init(
                    options.name,
                    definition,
                ),
            },
        }
    }

    fn rootModule() !void {}
};

test "Basic" {
    const some = struct {
        const doc = "Some module";
    };

    const mod1 = try Module.init(some, .{});
    const mod2 = try Module.init(some, .{});

    std.debug.print("Single: {}", .{mod1});
    std.debug.print("Multi: {}", .{mod2});
}
