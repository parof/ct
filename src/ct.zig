const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const os = std.os;
const args = @import("./args.zig");

const Task = struct {
    /// Name of the file to open.
    file_name: []const u8,
    /// Size to use for the chunk.
    chunk_size: u64,
    /// Offset in the input file.
    from: u64,
    /// Number of bytes to read.
    len: u64,
    /// Address for writing the answer for the ask.
    answer: *u64,
};

pub fn run(config: args.Config) !void {
    for (config.file_names.items) |file_name| {
        const lines = try runFile(file_name, config.threads, config.chunks_size);
        try std.io.getStdOut().writer().print("{d}: {s}\n", .{ lines, file_name });
    }
}

pub fn runFile(file_name: []const u8, threads: u64, chunks_size: u64) !u64 {
    // TODO: the last thread should be executed in the current thread, without spawning a new one.
    const file_size = try getFileSize(file_name);
    if (file_size == 0) return 0;

    // We set the number of threads to be the minimum between what was provided by the user and the file size.
    // If the file size is less than the number of threads and we ignore this, there are divisions by zero.
    const nthreads = std.math.min(threads, file_size);
    const avg_size = file_size / nthreads;

    // Prepare the array to write the results.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var alloc = arena.allocator();
    var answers: std.ArrayList(u64) = std.ArrayList(u64).init(alloc);
    defer answers.deinit();
    for (0..nthreads) |_| {
        try answers.append(0);
    }

    // Create the tasks.
    var tasks = std.ArrayList(Task).init(alloc);
    defer tasks.deinit();
    var initial_offset: u64 = 0;
    for (0..nthreads) |i| {
        const reminder: u64 = try std.math.rem(u64, file_size, avg_size);
        var current_size: u64 = avg_size;
        if (i < reminder) current_size += 1;
        const task = Task{ .file_name = file_name, .chunk_size = chunks_size, .from = initial_offset, .len = current_size, .answer = &(answers.items[i]) };
        try tasks.append(task);
        initial_offset += current_size;
    }

    // Spawn the threads.
    var threads_list = std.ArrayList(std.Thread).init(alloc);
    defer threads_list.deinit();
    for (tasks.items) |task| {
        var thread = try std.Thread.spawn(.{}, workerFunction, .{task});
        try threads_list.append(thread);
    }

    // Collect the results.
    for (threads_list.items) |thread| thread.join();
    var lines: u64 = 0;
    for (answers.items) |answer| lines += answer;
    return lines;
}

pub fn getFileSize(file_name: []const u8) !u64 {
    var file: fs.File = try fs.cwd().openFile(file_name, fs.File.OpenFlags{});
    defer file.close();
    const stat = try file.stat();
    return stat.size;
}

// Worker function run by each thread.
fn workerFunction(task: Task) !void {
    const lines = try countLinesChunk(task.file_name, task.from, task.len, task.chunk_size);
    task.answer.* = lines;
}

/// Counts the lines in [file_name] from [from] for [len] bytes. The buffered
/// read happens is a buffer of size [chunk_size]. Has to open the file with
/// [openFile].
pub fn countLinesChunk(file_name: []const u8, from: u64, len: u64, chunk_size: u64) !u64 {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var alloc = arena.allocator();
    const actual_chunk_size = if (len >= chunk_size) chunk_size else len;
    var chunk = try alloc.alloc(u8, actual_chunk_size);
    const open_flags = fs.File.OpenFlags{ .mode = .read_only, .lock = .None, .lock_nonblocking = true };
    var file = try fs.cwd().openFile(file_name, open_flags);
    defer file.close();
    try file.seekTo(from);
    var reader = file.reader();
    var bytes_read: usize = 0;
    var lines: u64 = 0;
    while (bytes_read < len) {
        var current_bytes_read = try reader.readAll(chunk);
        bytes_read += current_bytes_read;
        for (chunk[0..current_bytes_read]) |c| {
            if (c == '\n') {
                lines += 1;
            }
        }
    }
    return lines;
}

const testing = std.testing;
test "six lines" {
    try testRun(5, "tests/five-lines.txt", 2, 2048);
}
test "zero lines" {
    try testRun(0, "tests/zero-lines.txt", 2, 2014);
}
test "zero lines non-empty" {
    try testRun(0, "tests/zero-non-empty.txt", 2, 1024);
}
test "more threads than bytes" {
    try testRun(0, "tests/zero-lines.txt", 512, 1024);
}
fn testRun(expected: u64, file_name: []const u8, threads: u64, chunks_size: u64) !void {
    try testing.expectEqual(expected, try runFile(file_name, threads, chunks_size));
}
