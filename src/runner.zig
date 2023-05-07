const std = @import("std");
const fs = std.fs;
const args = @import("./args.zig");
const Config = @import("./args.zig").Config;
const lines = @import("./lines.zig");

const OUT_BUFFER_MAX_LEN = 1024;

pub const Runner = struct {
    const Self = @This();

    pub fn run(self: Self) !void {
        _ = self;
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var allocator = arena.allocator();
        defer arena.deinit();
        if (args.parse_args(allocator)) |config| {
            defer config.deinit();
            var config_runner = Runner{};
            var all_paths_exist = try config_runner.allPathsExist(config);
            std.debug.print("all paths exist: {any}\n", .{all_paths_exist});
            std.debug.print("all paths are directories: {any}\n", .{try config_runner.allPathsAreDirectories(config)});
            std.debug.print("all paths are files: {any}\n", .{try config_runner.allPathsAreFiles(config)});
        } else |err| {
            try args.printErrorMessage(err, std.io.getStdErr().writer());
            if (err != error.WantsHelp) {
                std.os.exit(1);
            }
        }
    }

    fn lines_main() !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var allocator = arena.allocator();
        defer arena.deinit();
        if (args.parse_args(allocator)) |config| {
            defer config.deinit();
            try lines.run(config);
        } else |err| {
            try args.printErrorMessage(err, std.io.getStdErr().writer());
            if (err != error.WantsHelp) {
                std.os.exit(1);
            }
        }
    }

    fn allPathsAreDirectories(self: Self, config: Config) !bool {
        return self.allPathsHaveTheSameKind(config, fs.File.Kind.Directory);
    }

    fn allPathsAreFiles(self: Self, config: Config) !bool {
        return self.allPathsHaveTheSameKind(config, fs.File.Kind.File);
    }

    fn allPathsHaveTheSameKind(self: Self, config: Config, kind: fs.File.Kind) !bool {
        _ = self;
        var cwd = fs.cwd();
        var out_buffer: [OUT_BUFFER_MAX_LEN]u8 = undefined;
        for (config.input_paths.items) |input_path| {
            var absolute_path = cwd.realpath(input_path, &out_buffer) catch return false;
            var file = try fs.openFileAbsolute(absolute_path, fs.File.OpenFlags{});
            var stat = try file.stat();
            if (stat.kind != kind) {
                return false;
            }
            file.close();
        }
        return true;
    }

    pub fn allPathsExist(self: Self, config: Config) !bool {
        _ = self;
        var cwd = fs.cwd();
        var out_buffer: [OUT_BUFFER_MAX_LEN]u8 = undefined;
        for (config.input_paths.items) |input_path| {
            var absolute_path = cwd.realpath(input_path, &out_buffer) catch |err| switch (err) {
                error.FileNotFound => return false,
                else => return err,
            };
            // If this cannot access one file, we just return false.
            _ = fs.accessAbsolute(absolute_path, fs.File.OpenFlags{}) catch return false;
        }
        return true;
    }
};
