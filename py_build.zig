const std = @import("std");

pub fn join(allocator: std.mem.Allocator, a: []const u8, b: []const u8) []const u8 {
    const len = a.len + b.len;
    var result = allocator.alloc(u8, len) catch unreachable;
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

const builtin = @import("builtin");

const path_separator = if (builtin.os.tag == .windows) "\\" else "/";

pub const PyBuild = struct {
    build: *std.Build,
    py: *std.Build.Module,
    install_dir: []const u8,

    pub fn init(b: *std.Build, py: *std.Build.Module, optal_install_dir: ?[]const u8) @This() {
        const install_dir_from_root = optal_install_dir orelse "out";
        const install_dir_from_prefix = join(b.allocator, ".." ++ path_separator, install_dir_from_root);

        return .{
            .build = b,
            .py = py,
            .install_dir = install_dir_from_prefix,
        };
    }

    pub const BuildOptions = struct {
        // NOTE: Copied from SharedLibraryOptions
        name: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        root_source_file: std.Build.LazyPath,
        code_model: std.builtin.CodeModel = .default,
        version: ?std.SemanticVersion = null,
        max_rss: usize = 0,
        single_threaded: ?bool = null,
        pic: ?bool = null,
        strip: ?bool = null,
        unwind_tables: ?bool = null,
        omit_frame_pointer: ?bool = null,
        sanitize_thread: ?bool = null,
        error_tracing: ?bool = null,

        // NOTE: Custom
        generate_stubs: bool = true,
        pyzi_import_name: []const u8 = "PyZi",
    };

    pub const Module = struct {
        compile: *std.Build.Step.Compile,
        install_artifact: *std.Build.Step.InstallArtifact,
    };

    pub fn addModule(self: *@This(), opts: BuildOptions) Module {
        if (opts.target.result.os.tag == .windows and opts.target.result.abi != .msvc) {
            std.debug.print("{s}\n", .{@tagName(opts.target.result.abi)});
            // TODO: Check if it hass to be msvc. If yes find solution
            // @panic("Only MSVC ABI is supported on Windows by Python");
        }
        const lib = self.build.addSharedLibrary(.{
            .name = opts.name,
            .root_source_file = opts.root_source_file,
            .target = opts.target,
            .optimize = opts.optimize,
            .code_model = opts.code_model,
            .version = opts.version,
            .max_rss = opts.max_rss,
            .single_threaded = opts.single_threaded,
            .pic = opts.pic,
            .strip = opts.strip,
            .unwind_tables = opts.unwind_tables,
            .omit_frame_pointer = opts.omit_frame_pointer,
            .sanitize_thread = opts.sanitize_thread,
            .error_tracing = opts.error_tracing,
            .link_libc = true,
        });

        lib.root_module.addImport(opts.pyzi_import_name, self.py);

        // TODO:
        // f"-femit-bin={self.get_ext_fullpath(ext.name)}",
        // "-fallow-shlib-undefined",

        const install_artifact = self.build.addInstallArtifact(lib, .{});
        self.build.getInstallStep().dependOn(&install_artifact.step);

        // Copy to install dir
        const build_dir = if (opts.target.result.os.tag == .windows) self.build.exe_dir else self.build.lib_dir;

        const src_path = join(
            self.build.allocator,
            join(self.build.allocator, build_dir, path_separator),
            install_artifact.artifact.out_filename,
        );

        const output_file = if (install_artifact.artifact.isDll()) blk: {
            break :blk join(self.build.allocator, opts.name, ".pyd");
        } else blk: {
            if (opts.target.result.isDarwin()) {
                break :blk join(self.build.allocator, opts.name, ".dylib");
            } else {
                break :blk join(self.build.allocator, opts.name, ".so");
            }
        };

        const output_path = join(
            self.build.allocator,
            join(self.build.allocator, self.install_dir, path_separator),
            output_file,
        );

        const install_dir = self.build.addInstallFileWithDir(.{ .cwd_relative = src_path }, .prefix, output_path);
        install_dir.step.dependOn(&install_artifact.step);
        self.build.getInstallStep().dependOn(&install_dir.step);

        // TODO: A way to generate types. Probably works similar to test runner?
        if (opts.generate_stubs) {}

        // NOTE: Send through module name as option
        const options = self.build.addOptions();
        options.addOption([]const u8, "name", opts.name);
        lib.root_module.addOptions("config", options);

        return .{
            .compile = lib,
            .install_artifact = install_artifact,
        };
    }

    pub const TestOptions = struct {
        name: []const u8 = "test",
        root_source_file: std.Build.LazyPath,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode = .Debug,
        version: ?std.SemanticVersion = null,
        max_rss: usize = 0,
        filters: []const []const u8 = &.{},
        single_threaded: ?bool = null,
        pic: ?bool = null,
        strip: ?bool = null,
        unwind_tables: ?bool = null,
        omit_frame_pointer: ?bool = null,
        sanitize_thread: ?bool = null,
        error_tracing: ?bool = null,
    };

    pub fn addTest(self: *@This(), opts: TestOptions) *std.Build.Step.Compile {
        if (opts.target.result.os.tag == .windows and opts.target.result.abi != .msvc) {
            // TODO: Check if it has to be msvc. If yes find solution
            // @panic("Only MSVC ABI is supported on Windows by Python");
        }
        const t = self.build.addTest(.{
            .name = opts.name,
            .root_source_file = opts.root_source_file,
            .target = opts.target,
            .optimize = opts.optimize,
            .version = opts.version,
            .max_rss = opts.max_rss,
            .filters = opts.filters,
            .single_threaded = opts.single_threaded,
            .pic = opts.pic,
            .strip = opts.strip,
            .unwind_tables = opts.unwind_tables,
            .omit_frame_pointer = opts.omit_frame_pointer,
            .sanitize_thread = opts.sanitize_thread,
            .error_tracing = opts.error_tracing,
            // TODO: Replace with custom test runner
            // .test_runner = self.build.path("py_test.zig"),
            .link_libc = true,
        });
        t.root_module.addImport("PyZi", self.py);

        // NOTE: Send through module name as option
        const options = self.build.addOptions();
        options.addOption([]const u8, "name", opts.name);
        t.root_module.addOptions("config", options);

        return t;
    }
};
