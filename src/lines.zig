/// This module provides the functionality to count the lines in a single source
/// file.

const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const os = std.os;
const args = @import("./args.zig");

const CountLinesTask = struct {
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
    /// The first byte to read in the task is the beginning of an UTF-8 symbol.
    first_byte_is_utf8_synchronized: bool
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

    // Prepare the array to write the results.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var alloc = arena.allocator();
    var answers: std.ArrayList(u64) = std.ArrayList(u64).init(alloc);
    defer answers.deinit();
    for (0..nthreads) |_| {
        try answers.append(0);
    }

    var tasks = try createTasks(alloc, file_name, chunks_size, nthreads, file_size, answers);
    defer tasks.deinit();

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

/// Create the tasks evenly distributed for the number of threads.
/// The caller owns the `ArrayList` of tasks, and must deallocate it.
fn createTasks(
    alloc: std.mem.Allocator, 
    file_name: []const u8, 
    chunks_size: usize, 
    nthreads: usize, 
    file_size: usize, 
    answers: std.ArrayList(u64)
) !std.ArrayList(CountLinesTask) {
    const avg_size = file_size / nthreads;
    var tasks = std.ArrayList(CountLinesTask).init(alloc);
    var initial_offset: u64 = 0;
    for (0..nthreads) |i| {
        const reminder: u64 = try std.math.rem(u64, file_size, avg_size);
        var current_size: u64 = avg_size;
        if (i < reminder) current_size += 1;

        var first_byte_is_utf8_synchronized = true;
        if (initial_offset > 0) {
            // We have to check the byte previous to the current one: if it 
            // starts with a 1, the first byte in the current tasks will be part
            // of the previous UTF-8 character.
            const open_flags = fs.File.OpenFlags{ .mode = .read_only, .lock = .None, .lock_nonblocking = true };
            var file = try fs.cwd().openFile(file_name, open_flags);
            try file.seekTo(initial_offset - 1);
            var reader = file.reader();
            const previous_byte = try reader.readByte();
            // If the byte before the first one begins with a 1, then the first
            // byte in the task will be part of the previous UTF-8 character.
            const previous_byte_starts_with_one = previous_byte & 0b10000000 == 0b10000000;
            first_byte_is_utf8_synchronized = previous_byte_starts_with_one == false;
            file.close();
        }

        const task = CountLinesTask{ 
            .file_name = file_name, 
            .chunk_size = chunks_size, 
            .from = initial_offset, 
            .len = current_size, 
            .answer = &(answers.items[i]),
            .first_byte_is_utf8_synchronized = first_byte_is_utf8_synchronized
        };
        try tasks.append(task);
        initial_offset += current_size;
    }
    return tasks;
}

// Worker function run by each thread.
fn workerFunction(task: CountLinesTask) !void {
    const lines = try countLinesChunk(task.file_name, task.from, task.len, task.chunk_size, task.first_byte_is_utf8_synchronized);
    task.answer.* = lines;
}

/// Counts the lines in [file_name] from [from] for [len] bytes. The buffered
/// read happens is a buffer of size [chunk_size]. Has to open the file with
/// [openFile].
pub fn countLinesChunk(file_name: []const u8, from: u64, len: u64, chunk_size: u64, first_byte_is_utf8_synchronized: bool) !u64 {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    var alloc = arena.allocator();

    // Allocate the chunk that will be used for the buffered reads.
    const actual_chunk_size = if (len >= chunk_size) chunk_size else len;
    var chunk = try alloc.alloc(u8, actual_chunk_size);

    // Prepare the file and the reader.
    const open_flags = fs.File.OpenFlags{ .mode = .read_only, .lock = .None, .lock_nonblocking = true };
    var file = try fs.cwd().openFile(file_name, open_flags);
    defer file.close();
    try file.seekTo(from);
    var reader = file.reader();

    // Synchronize the UTF-8 stream.
    var bytes_read: usize = 0;
    if (!first_byte_is_utf8_synchronized) {
        bytes_read = try syncReaderWithUtf8Sequence(reader);
    }

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

/// Reads bytes until encounters a byte which has a leading 0. Such bytes in
/// UTF-8 encoding represent the end of a sequence of bytes that encode a
/// character. This method positions the file pointer to the byte next to the
/// first byte that has a leading 0. This function reads at least one byte.
/// Returns the number of bytes that are read.
fn syncReaderWithUtf8Sequence(reader: fs.File.Reader) !usize {
    var read = try reader.readByte();
    var bytes_read: usize = 1;
    var first_bit_is_zero = read & 0b1000000 == 0b00000000;

    // Discard until the first bit of the byte that we read is not 0.
    while (!first_bit_is_zero) {
        read = try reader.readByte();
        first_bit_is_zero = read & 0b1000000 == 0b00000000;
        bytes_read += 1;
    }
    return bytes_read;
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
test "utf-8" {
    try testRun(3, "tests/utf-8.txt", 4, 1024);
}
test "utf-8 with circle" {
    try testRun(0, "tests/utf-8-2.txt", 1, 1024);
}
fn testRun(expected: u64, file_name: []const u8, threads: u64, chunks_size: u64) !void {
    try testing.expectEqual(expected, try runFile(file_name, threads, chunks_size));
}
