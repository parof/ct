/// This module provides the functionality to count the number of lines for
/// source code.
const std = @import("std");
const fs = std.fs;

pub fn main(absolute_path: []const u8) !void {
    var myDir = try fs.openDirAbsolute(absolute_path, fs.Dir.OpenDirOptions{});
    var iterablePwd = try myDir.openIterableDir(".", fs.Dir.OpenDirOptions{});
    defer iterablePwd.close();
    std.debug.print("(dir) {s}\n", .{absolute_path});
    try depthFirstWalk(iterablePwd, 0);
    std.debug.print("\nDone!\n", .{});
}

fn depthFirstWalk(dir: fs.IterableDir, nesting: usize) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        for (0..nesting) |_| {
            std.debug.print("\t", .{});
        }
        switch (entry.kind) {
            .File => std.debug.print("[file] {s}\n", .{entry.name}),
            .Directory => {
                std.debug.print("(dir) {s}\n", .{entry.name});
                var subdir = try dir.dir.openIterableDir(entry.name, fs.Dir.OpenDirOptions{});
                try depthFirstWalk(subdir, nesting + 1);
                subdir.close();
            },
            .SymLink => std.debug.print("(symlink) {s}\n", .{entry.name}),
            else => std.debug.print("Shit!\n", .{}),
        }
    }
}
