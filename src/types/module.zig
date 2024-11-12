const c = @import("../c.zig");
const types = @import("root.zig");

pub const Module = struct {
    py: *const c.PyObject,

    const Errors = error{
        AddFailed,
        ExecFailed,
        InitializationFailed,
        CreationFailed,
        CannotCreateFromModuleDefAndSpec,
        CouldNotSetDocString,
        CouldNotGetDef,
        CouldNotGetDict,
        CouldNotGetFilename,
        CouldNotGetName,
        CouldNotGetState,
    };

    pub inline fn new(name: [:0]const u8) Errors!Module {
        return .{
            .py = c.PyModule_New(
                name.ptr,
            ) orelse return Errors.CreationFailed,
        };
    }

    pub inline fn newObject(name: types.String) Errors!Module {
        return .{
            .py = c.PyModule_NewObject(
                name.py,
            ) orelse return Errors.CreationFailed,
        };
    }

    pub inline fn init(def: *c.PyModuleDef) Errors!Module {
        return .{
            .d = c.PyModuleDef_Init(def.py) orelse return Errors.InitializationFailed,
        };
    }

    pub inline fn createEx(self: *c.PyModuleDef, api_version: c_int) Errors!Module {
        return .{
            .py = c.PyModule_Create2(
                self.py,
                api_version,
            ) orelse return Errors.CreationFailed,
        };
    }

    pub inline fn fromDefAndSpecEx(def: *c.PyModuleDef, spec: types.Object, api_version: c_int) Errors!Module {
        return .{
            .py = c.PyModule_FromDefAndSpec2(
                def.py,
                spec.py,
                api_version,
            ) orelse return Errors.CannotCreateFromModuleDefAndSpec,
        };
    }

    pub inline fn add(self: @This(), name: [:0]const u8, value: types.Object) Errors!void {
        if (c.PyModule_Add(self.py, name.ptr, value.py) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn addObjectRef(self: @This(), name: [:0]const u8, value: types.Object) Errors!void {
        if (c.PyModule_AddObjectRef(self.py, name.ptr, value.py) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn addType(self: @This(), value: types.Type) Errors!void {
        if (c.PyModule_AddType(self.py, value.py) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn addFunctions(self: @This(), methods: [:.{}]types.Function.Def) Errors!void {
        if (c.PyModule_AddFunctions(self.py, @ptrCast(methods.ptr)) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn addIntConstant(self: @This(), name: [:0]const u8, value: anytype) Errors!void {
        if (@typeInfo(@TypeOf(value)) != .Int) {
            @compileError("Expected an integer value");
        }

        if (c.PyModule_AddIntConstant(self.py, name.ptr, @intCast(value)) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn addStringConstant(self: @This(), name: [:0]const u8, value: [:0]const u8) Errors!void {
        if (c.PyModule_AddStringConstant(self.py, name.ptr, value.ptr) < 0) {
            return Errors.AddFailed;
        }
    }

    pub inline fn execDef(self: @This(), def: *c.PyModuleDef) Errors!void {
        if (c.PyModule_ExecDef(self.py, def.py) < 0) {
            return Errors.ExecFailed;
        }
    }

    pub inline fn setDocString(self: @This(), doc: [:0]const u8) Errors!void {
        if (c.PyModule_SetDocString(self.py, doc.ptr) < 0) {
            return Errors.CouldNotSetDocString;
        }
    }

    pub inline fn getDef(self: @This()) Errors!*c.PyModuleDef {
        return .{
            .py = c.PyModule_GetDef(self.py) orelse return Errors.CouldNotGetDef,
        };
    }

    pub inline fn getDict(self: @This()) Errors!types.Dict {
        return .{
            .py = c.PyModule_GetDict(self.py) orelse return Errors.CouldNotGetDict,
        };
    }

    pub inline fn getFilename(self: @This()) Errors![*]const u8 {
        return c.PyModule_GetFilename(self.py) orelse return Errors.CouldNotGetFilename;
    }

    pub inline fn getFilenameObject(self: @This()) Errors!types.String {
        return .{
            .py = c.PyModule_GetFilenameObject(self.py) orelse return Errors.CouldNotGetFilename,
        };
    }

    pub inline fn getName(self: @This()) Errors![*]const u8 {
        return c.PyModule_GetName(self.py) orelse return Errors.CouldNotGetName;
    }

    pub inline fn getNameObject(self: @This()) Errors!types.String {
        return .{
            .py = c.PyModule_GetNameObject(self.py) orelse return Errors.CouldNotGetName,
        };
    }

    pub inline fn getState(self: @This()) Errors!*anyopaque {
        return c.PyModule_GetState(self.py) orelse return Errors.CouldNotGetState;
    }
};
