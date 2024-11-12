const std = @import("std");
const c = @import("../c.zig");

pub const Def = extern struct {
    name: ?[*]const u8 = null,
    method: c.PyCFunction = null,
    flags: Flags = .{},
    doc: ?[*]const u8 = null,
};

test "Check if Equal" {
    try std.testing.expectEqual(@sizeOf(c.PyMethodDef), @sizeOf(Def));

    const def1 = Def{
        .name = "test",
        .method = null,
        .flags = Flags{ .VariableArguemnts = true },
        .doc = "This is a test function",
    };

    const def2 = c.PyMethodDef{
        .ml_name = "test",
        .ml_meth = null,
        .ml_flags = 1,
        .ml_doc = "This is a test function",
    };

    const def1_cast: c.PyMethodDef = @bitCast(def1);
    const def2_cast: Def = @bitCast(def2);

    try std.testing.expectEqualDeep(def2, def1_cast);
    try std.testing.expectEqualDeep(def1, def2_cast);
}

pub const Flags = packed struct(c_int) {
    VariableArguemnts: bool = false,
    KeywordArguements: bool = false,
    NoArguments: bool = false,
    OneArguement: bool = false,
    ClassMethod: bool = false, // @classmethod
    StaticMethod: bool = false, // @staticmethod
    CoExist: bool = false,
    FastCall: bool = false,
    __u9: u1 = 0,
    Method: bool = false,
    __unused: u22 = 0,

    fn isValidPermutation(self: *const @This()) bool {
        if (@as(u32, @bitCast(self.*)) == 0) return false;

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

    // TODO: Convert Bool to valid type
    fn getSignature(self: *const @This()) !type {
        if (@as(u32, @bitCast(self.*)) == 0) return error.InvalidFnFlagPermutation;

        // METH_VARARGS
        if (self.VariableArguemnts and
            !self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            !self.FastCall and
            !self.Method) return bool;

        // METH_KEYWORDS
        if (!self.VariableArguemnts and
            self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            !self.FastCall and
            !self.Method) return bool;

        // METH_VARARGS | METH_KEYWORDS
        if (self.VariableArguemnts and
            self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            !self.FastCall and
            !self.Method) return bool;

        // METH_FASTCALL
        if (!self.VariableArguemnts and
            !self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            self.FastCall and
            !self.Method) return bool;

        // METH_FASTCALL | METH_KEYWORDS
        if (!self.VariableArguemnts and
            self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            self.FastCall and
            !self.Method) return bool;

        // METH_METHOD
        if (!self.VariableArguemnts and
            !self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            !self.FastCall and
            self.Method) return bool;

        // METH_METHOD | METH_FASTCALL | METH_KEYWORDS
        if (!self.VariableArguemnts and
            self.KeywordArguements and
            !self.NoArguments and
            !self.OneArguement and
            self.FastCall and
            self.Method) return bool;

        // METH_NOARGS
        if (!self.VariableArguemnts and
            !self.KeywordArguements and
            self.NoArguments and
            !self.OneArguement and
            !self.FastCall and
            !self.Method) return bool;

        // METH_O
        if (!self.VariableArguemnts and
            !self.KeywordArguements and
            !self.NoArguments and
            self.OneArguement and
            !self.FastCall and
            !self.Method) return bool;

        return error.InvalidFnFlagPermutation;
    }

    // Can be changed by user using fn_flags declaration.
    // Function that can merge get the default flags with user flags of a function.
    // Guaranteed to be a valid permutation.
    // TODO:
    pub fn getFlags(sig: type) !@This() {
        _ = sig;
    }

    // Guaranteed to be a valid permutation
    pub fn mergeFlags(self: *const @This(), other: @This()) !@This() {
        const self_cast: u32 = @bitCast(self.*);
        const other_cast: u32 = @bitCast(other);
        const merged: @This() = @bitCast(self_cast | other_cast);

        if (!merged.isValidPermutation()) {
            return error.InvalidFnFlagPermutation;
        }
        return merged;
    }
};

test "Flags Checked with METH_*" {
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

    const f1: c_int = @bitCast(Flags{ .VariableArguemnts = true });
    try std.testing.expectEqual(METH_VARARGS, f1);

    const f2: c_int = @bitCast(Flags{ .KeywordArguements = true });
    try std.testing.expectEqual(METH_KEYWORDS, f2);

    const f3: c_int = @bitCast(Flags{ .NoArguments = true });
    try std.testing.expectEqual(METH_NOARGS, f3);

    const f4: c_int = @bitCast(Flags{ .OneArguement = true });
    try std.testing.expectEqual(METH_O, f4);

    const f5: c_int = @bitCast(Flags{ .ClassMethod = true });
    try std.testing.expectEqual(METH_CLASS, f5);

    const f6: c_int = @bitCast(Flags{ .StaticMethod = true });
    try std.testing.expectEqual(METH_STATIC, f6);

    const f7: c_int = @bitCast(Flags{ .CoExist = true });
    try std.testing.expectEqual(METH_COEXIST, f7);

    const f8: c_int = @bitCast(Flags{ .FastCall = true });
    try std.testing.expectEqual(METH_FASTCALL, f8);

    const f9: c_int = @bitCast(Flags{});
    try std.testing.expectEqual(METH_STACKLESS, f9);

    const f10: c_int = @bitCast(Flags{ .Method = true });
    try std.testing.expectEqual(METH_METHOD, f10);
}

test "Merge Flags" {
    const f1 = Flags{ .VariableArguemnts = true };
    const f2 = Flags{ .KeywordArguements = true };

    const expected = Flags{ .VariableArguemnts = true, .KeywordArguements = true };
    const merged = try f1.mergeFlags(f2);

    try std.testing.expectEqual(expected, merged);
}
