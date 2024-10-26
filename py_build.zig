const std = @import("std");

pub const PyBuild = struct {
    build: *std.Build,
    py: *std.Build.Module,

    pub fn init(b: *std.Build, py: *std.Build.Module) @This() {
        return .{
            .build = b,
            .py = py,
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
        install_dir: []const u8 = "lib",
    };

    pub const Module = struct {
        compile: *std.Build.Step.Compile,
        install_artifact: *std.Build.Step.InstallArtifact,
    };

    pub fn addModule(self: *@This(), opts: BuildOptions) Module {
        var target = opts.target;
        if (opts.target.result.os.tag == .windows) {
            var query = target.query;
            query.abi = .msvc;
            target = self.build.resolveTargetQuery(query);
        }

        const lib = self.build.addSharedLibrary(.{
            .name = opts.name,
            .root_source_file = opts.root_source_file,
            .target = target,
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

        const install_dir: std.Build.InstallDir = .{ .custom = opts.install_dir };

        const install_artifact = self.build.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = install_dir.dupe(self.build) },
            // .pdb_dir = .{ .override = install_dir.dupe(self.build) },
            // .h_dir = .{ .override = install_dir.dupe(self.build) },
            // .implib_dir = .{ .override = install_dir.dupe(self.build) },
        });
        self.build.getInstallStep().dependOn(&install_artifact.step);

        // TODO: A way to generate types. Probably works similar to test runner?
        if (opts.generate_stubs) {}

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
        var target = opts.target;
        if (opts.target.result.os.tag == .windows) {
            var query = target.query;
            query.abi = .msvc;
            target = self.build.resolveTargetQuery(query);
        }

        const t = self.build.addTest(.{
            .name = opts.name,
            .root_source_file = opts.root_source_file,
            .target = target,
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
            .test_runner = self.build.path("py_test.zig"),
            .link_libc = true,
        });
        t.root_module.addImport("PyZi", self.py);

        return t;
    }
};
