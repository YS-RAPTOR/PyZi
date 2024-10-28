pub usingnamespace @cImport({
    @cInclude("Python.h");
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cDefine("Py_LIMITED_API", "3");
});
