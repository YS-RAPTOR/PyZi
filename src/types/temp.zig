const c = @import("../c.zig");

//DONE:

// TODO:

pub const Type = struct {
    py: *const c.PyTypeObject,
};

pub const Object = struct {
    py: *const c.PyObject,
};

pub const Dict = struct {
    py: *const c.PyObject,
};

pub const String = struct {
    py: *const c.PyObject,
};
