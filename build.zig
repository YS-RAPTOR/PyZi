const std = @import("std");
const join = @import("py_build.zig").join;

// "zig",
// *(
// ),
// ext.sources[0],

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const python_exe = b.option(
        []const u8,
        "python_exe",
        "Path to the python executable",
    ) orelse "python";
    const py_info = getPythonInfo(b, python_exe) catch unreachable;

    // NOTE: Lib
    const LibPyZi = b.addSharedLibrary(.{
        .name = "PyZi",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    LibPyZi.root_module.linkSystemLibrary(py_info.python_package, .{
        .needed = true,
        .search_strategy = .no_fallback,
    });

    LibPyZi.root_module.addIncludePath(.{ .cwd_relative = py_info.include_path });
    LibPyZi.root_module.addIncludePath(.{ .cwd_relative = py_info.other_include_path });
    LibPyZi.root_module.addLibraryPath(.{ .cwd_relative = py_info.lib_path });
    LibPyZi.root_module.addLibraryPath(.{ .cwd_relative = py_info.other_lib_path });
    LibPyZi.root_module.addLibraryPath(.{ .cwd_relative = py_info.base_path });

    const options = b.addOptions();
    options.addOption([]const u8, "module_name", "PyZi");
    options.addOption([]const u8, "python_version", "0x030d00f0");
    LibPyZi.root_module.addOptions("config", options);

    b.installArtifact(LibPyZi);

    // NOTE: Tests
    const TestPyZi = b.addTest(.{
        .name = "PyZi",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    TestPyZi.root_module.linkSystemLibrary(py_info.python_package, .{
        .needed = true,
        .search_strategy = .no_fallback,
    });
    TestPyZi.addIncludePath(.{ .cwd_relative = py_info.include_path });
    TestPyZi.addIncludePath(.{ .cwd_relative = py_info.other_include_path });
    TestPyZi.addLibraryPath(.{ .cwd_relative = py_info.lib_path });
    TestPyZi.addLibraryPath(.{ .cwd_relative = py_info.other_lib_path });
    TestPyZi.addLibraryPath(.{ .cwd_relative = py_info.base_path });
    TestPyZi.root_module.addOptions("config", options);

    const run_test_pyzi = b.addRunArtifact(TestPyZi);
    const test_step = b.step("test", "Run PyZi tests");
    test_step.dependOn(&run_test_pyzi.step);

    @import("build_examples.zig").build(b, &LibPyZi.root_module, &target, &optimize);
}

fn getPythonInfo(b: *std.Build, python_exe: []const u8) !struct {
    python_package: []const u8,
    include_path: []const u8,
    other_include_path: []const u8,
    lib_path: []const u8,
    other_lib_path: []const u8,
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
        .other_include_path = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import os; import sysconfig; print( os.path.join( os.path.join(sysconfig.get_config_var(\"installed_base\"), \"include\"), \"python\" + sysconfig.get_config_var(\"VERSION\"),), end=\"\",)",
            },
        })).stdout,
        .other_lib_path = (try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{
                python_exe,
                "-c",
                "import os; import sysconfig; print(os.path.join(sysconfig.get_config_var(\"installed_base\"), \"lib\"), end=\"\")",
            },
        })).stdout,
    };
}
