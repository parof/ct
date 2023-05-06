const std = @import("std");
const mem = std.mem;
const os = std.os;

const HELP_LONG_FLAG: []const u8 = "--help";
const HELP_SHORT_FLAG: []const u8 = "-h";
const DEFAULT_NUMBER_OF_THREADS: u64 = 1;
const DEFAULT_CHUNKS_SIZE: u64 = 1024 * 1024 * 2; // 2Mb by default.
const THREADS_LONG_FLAG: []const u8 = "--threads";
const THREADS_SHORT_FLAG: []const u8 = "-t";
const CHUNKS_LONG_FLAG: []const u8 = "--chunks-size";
const CHUNKS_SHORT_FLAG: []const u8 = "-c";

pub const CountLinesConfig = struct {
    file_names: std.ArrayList([]const u8),
    threads: u64 = DEFAULT_NUMBER_OF_THREADS,
    chunks_size: u64 = DEFAULT_CHUNKS_SIZE,

    pub fn deinit(self: CountLinesConfig) void {
        self.file_names.deinit();
    }
};


pub const ParseArgsError = error{ 
    /// The user did not provide an input file.
    FilePathNotProvided, 
    /// The user did not provide an argument for the thread option.
    ThreadOptionExpectsArgument, 
    /// The user did not provide an integer argument for the thread option.
    ThreadOptionExpectsInteger, 
    /// The user did not provide an argument for the chunks size option.
    ChunksSizeOptionExpectsArgument, 
    /// The user did not provide an integer argument for the chunks size option.
    ChunksSizeOptionExpectsInteger,
    /// The user wants to print the help message.
    WantsHelp
};

pub fn parse_args(allocator: mem.Allocator) ParseArgsError!CountLinesConfig {
    var threads: u64 = DEFAULT_NUMBER_OF_THREADS;
    var chunks_size: u64 = DEFAULT_CHUNKS_SIZE;
    var file_names = std.ArrayList([]const u8).init(allocator);
    errdefer file_names.deinit();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = arena.allocator();
    defer arena.deinit();
    var iter = std.process.argsWithAllocator(alloc) catch unreachable;
    defer iter.deinit();
    _ = iter.next(); // Skip the name of the program.
    while (iter.next()) |arg| {
        if (mem.eql(u8, arg, HELP_LONG_FLAG) or mem.eql(u8, arg, HELP_SHORT_FLAG)) {
            return error.WantsHelp;
        } else if (mem.eql(u8, arg, THREADS_LONG_FLAG) or mem.eql(u8, arg, THREADS_SHORT_FLAG)) {
            // Set the threads.
            threads = try parse_numeric_arg(&iter, error.ThreadOptionExpectsArgument, error.ThreadOptionExpectsInteger);
        } else if (mem.eql(u8, arg, CHUNKS_LONG_FLAG) or mem.eql(u8, arg, CHUNKS_SHORT_FLAG)) {
            // Set the chunks.
            chunks_size = try parse_numeric_arg(&iter, error.ChunksSizeOptionExpectsArgument, error.ChunksSizeOptionExpectsInteger);
        } else {
            // Set the name of the file.
            file_names.append(arg) catch std.process.exit(1);
        }
    }
    if (file_names.items.len == 0) {
        return error.FilePathNotProvided;
    } else {
        return CountLinesConfig{
            .file_names = file_names,
            .threads = threads,
            .chunks_size = chunks_size,
        };
    }
}

fn parse_numeric_arg(
        iter: *std.process.ArgIterator, 
        missing_arg_error: ParseArgsError, 
        parse_integer_error: ParseArgsError
) ParseArgsError!u64 {
    var val = iter.next() orelse return missing_arg_error;
    return std.fmt.parseInt(u64, val, 10) catch return parse_integer_error;
}

pub fn printErrorMessage(err: ParseArgsError, writer: std.fs.File.Writer) !void {
    switch (err) {
        error.WantsHelp => { },
        error.FilePathNotProvided => {
            try writer.print("Must provide an input file.\n", .{});
            try writer.print("\n", .{});
        },
        error.ThreadOptionExpectsArgument, error.ThreadOptionExpectsInteger => {
            try writer.print("{s} and {s} options expect an argument.\n", .{ THREADS_LONG_FLAG, THREADS_SHORT_FLAG });
            try writer.print("\n", .{});
        },
        error.ChunksSizeOptionExpectsArgument, error.ChunksSizeOptionExpectsInteger => {
            try writer.print("{s} and {s} options expect an integer argument.\n", .{ CHUNKS_LONG_FLAG, CHUNKS_SHORT_FLAG });
            try writer.print("\n", .{});
        },
    }
    try printHelpMessage(writer);
}

pub fn printHelpMessage(writer: std.fs.File.Writer) !void {
    try writer.print("usage: ct [OPTIONS] [input]...\n", .{});
    try writer.print("OPTIONS\n", .{});
    try writer.print("\t{s},{s} <threads>\t\tSets the number of threads to use. (default: {d})\n", .{ THREADS_LONG_FLAG, THREADS_SHORT_FLAG, DEFAULT_NUMBER_OF_THREADS });
    try writer.print("\t{s},{s} <chunks-size>\tSets the size (in bytes) of the chunks allocated. (default: {d}Kb)\n", .{ CHUNKS_LONG_FLAG, CHUNKS_SHORT_FLAG, DEFAULT_CHUNKS_SIZE / 1024 });
    try writer.print("\t{s},{s} \t\t\tPrints the help message.\n", .{ HELP_LONG_FLAG, HELP_SHORT_FLAG });
    try writer.print("ARGS\n", .{});
    try writer.print("\t<input>\t\tPath to the input file(s).\n", .{});
}
