const std = @import("std");
const py_build = @import("py_build.zig");

pub fn build(
    b: *std.Build,
    PyZi: *std.Build.Module,
    target: *const std.Build.ResolvedTarget,
    optimize: *const std.builtin.OptimizeMode,
) void {
    // NOTE: Example to create a python module
    const build_step = b.step("examples", "Build examples");

    var py = py_build.PyBuild.init(b, PyZi, null);
    _ = py.addModule(.{
        .name = "Test",
        .root_source_file = b.path("examples/test.zig"),
        .target = target.*,
        .optimize = optimize.*,
        .dependsOn = build_step,
    });

    const mod_test = py.addTest(.{
        .name = "Test",
        .root_source_file = b.path("examples/test.zig"),
        .target = target.*,
        .optimize = optimize.*,
    });

    const run_lib_unit_tests = b.addRunArtifact(mod_test);
    const test_step = b.step("test-examples", "Run examples");
    test_step.dependOn(&run_lib_unit_tests.step);
}
