const std = @import("std");
const py_build = @import("py_build.zig");
const join = py_build.join;

// "zig",
// *(
// ),
// ext.sources[0],

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // NOTE: Creates the PyZi module that can be imported as a dependency

    const PyZi = b.addModule("PyZi", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const python_exe = b.option(
        []const u8,
        "python_exe",
        "Path to the python executable",
    ) orelse "python";

    const py_info = getPythonInfo(b, python_exe) catch unreachable;

    PyZi.addImport("self", PyZi);
    PyZi.linkSystemLibrary(py_info.python_package, .{
        .needed = true,
        .search_strategy = .no_fallback,
    });

    PyZi.addIncludePath(.{ .cwd_relative = py_info.include_path });
    PyZi.addLibraryPath(.{ .cwd_relative = py_info.lib_path });
    PyZi.addLibraryPath(.{ .cwd_relative = py_info.base_path });

    // NOTE: For LSP to work

    const LibPyZi = b.addSharedLibrary(.{
        .name = "PyZi",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    LibPyZi.root_module.addImport("self", &LibPyZi.root_module);
    LibPyZi.root_module.linkSystemLibrary(py_info.python_package, .{
        .needed = true,
        .search_strategy = .no_fallback,
    });

    LibPyZi.root_module.addIncludePath(.{ .cwd_relative = py_info.include_path });
    LibPyZi.root_module.addLibraryPath(.{ .cwd_relative = py_info.lib_path });
    LibPyZi.root_module.addLibraryPath(.{ .cwd_relative = py_info.base_path });
    b.installArtifact(LibPyZi);

    // NOTE: Example to create a python module

    const should_compile = b.option(
        bool,
        "compile",
        "Compile PyZi modules",
    ) orelse true;

    if (should_compile) {
        var py = py_build.PyBuild.init(b, PyZi, null);
        _ = py.addModule(.{
            .name = "Test",
            .root_source_file = b.path("tests/test.zig"),
            .target = target,
            .optimize = optimize,
        });

        const mod_test = py.addTest(.{
            .name = "Test",
            .root_source_file = b.path("tests/test.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_lib_unit_tests = b.addRunArtifact(mod_test);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
    }
}

fn getPythonInfo(b: *std.Build, python_exe: []const u8) !struct {
    python_package: []const u8,
    include_path: []const u8,
    lib_path: []const u8,
    base_path: []const u8,
} {
    _ = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ python_exe, "--version" },
    }) catch @panic("Missing python");

    return .{
        .python_package = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import sysconfig; print(\"python\" + sysconfig.get_config_var(\"VERSION\"), end=\"\")",
            },
        })).stdout,
        .include_path = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import sysconfig; print(sysconfig.get_config_var(\"INCLUDEPY\"), end=\"\")",
            },
        })).stdout,
        .lib_path = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import sysconfig; print(sysconfig.get_config_var(\"LIBDIR\"), end=\"\"),",
            },
        })).stdout,
        .base_path = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import sysconfig; print(sysconfig.get_config_var(\"installed_base\"), end=\"\")",
            },
        })).stdout,
    };
}
