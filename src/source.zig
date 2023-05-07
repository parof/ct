/// This module provides the functionality to count the number of lines for
/// source code.
const std = @import("std");
const fs = std.fs;
const debug = std.debug;
const log = std.log;
const heap = std.heap;
const mem = std.mem;

pub fn main(absolute_path: []const u8) !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var allocator = arena.allocator();
    var worklist = std.ArrayList([]const u8).init(allocator);

    var timer = try std.time.Timer.start();
    var myDir = try fs.openDirAbsolute(absolute_path, fs.Dir.OpenDirOptions{});
    var iterablePwd = try myDir.openIterableDir(".", fs.Dir.OpenDirOptions{});
    defer iterablePwd.close();
    try depthFirstWalk(iterablePwd, 0, &worklist, allocator);
    std.debug.print("Time to build worklist:  {d}ns\n", .{timer.read()});
    timer.reset();

    var threads_list = std.ArrayList(std.Thread).init(allocator);
    defer threads_list.deinit();
    for (0..8) |_| {
        var thread = try std.Thread.spawn(.{}, dummy, .{});
        try threads_list.append(thread);
    }
    for (threads_list.items) |thread| {
        thread.join();
    }
    std.debug.print("Time to create threads:     {d}ns\n", .{timer.read()});
    timer.reset();

    for (worklist.items) |filename| {
        var lines = try getLines(filename);
        _ = lines;
    }
    std.debug.print("Time to read the stuff: {d}ns\n", .{timer.read()});
}

var out_buffer: [1024]u8 = undefined;

fn depthFirstWalk(dir: fs.IterableDir, nesting: usize, worklist: *std.ArrayList([]const u8), allocator: mem.Allocator) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .File => {
                // if (std.mem.endsWith(u8, entry.name, ".rs")) {
                const absolutePath = try dir.dir.realpath(entry.name, &out_buffer);
                const ownedSlice = try allocator.alloc(u8, absolutePath.len);
                @memcpy(ownedSlice, absolutePath);
                try worklist.*.append(ownedSlice);
                // }
            },
            .Directory => {
                var subdir = try dir.dir.openIterableDir(entry.name, fs.Dir.OpenDirOptions{});
                try depthFirstWalk(subdir, nesting + 1, worklist, allocator);
                subdir.close();
            },
            .SymLink => {},
            else => {},
        }
    }
}

// TODO: this is a mayor improvement for performance.
// var buffer: [1024 * 1024 * 2]u8 = undefined;

/// Countes the lines in [file_name].
fn getLines(file_name: []const u8) !u64 {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var allocator = arena.allocator();
    var buffer = try allocator.alloc(u8, 1024 * 1024 * 2);

    // Prepare the file and the reader.
    const open_flags = fs.File.OpenFlags{ .mode = .read_only, .lock = .None, .lock_nonblocking = true };
    var file = try fs.cwd().openFile(file_name, open_flags);
    defer file.close();
    try file.seekTo(0);
    var reader = file.reader();

    var lines: u64 = 0;
    var bytes_read: usize = 0;
    var file_stats = try file.stat();
    while (bytes_read < file_stats.size) {
        var current_bytes_read = try reader.readAll(buffer);
        bytes_read += current_bytes_read;
        for (buffer[0..current_bytes_read]) |c| {
            if (c == '\n') {
                lines += 1;
            }
        }
    }
    return lines;
}

fn dummy() void {}
