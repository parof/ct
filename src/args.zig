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

/// Configuration for the execution of `ct`.
pub const Config = struct {
    input_paths: std.ArrayList([]const u8),
    threads: u64 = DEFAULT_NUMBER_OF_THREADS,
    chunks_size: u64 = DEFAULT_CHUNKS_SIZE,

    const Self = @This();

    /// Deinit with `config.deinit()`.
    pub fn init(allocator: mem.Allocator) Self {
        return Config {
            .input_paths = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: Config) void {
        self.input_paths.deinit();
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

/// Parses the arguments provided in `argv`. The caller owns the result
/// configuration, and has to deallocate it with `deinit`.
pub fn parse_args(allocator: mem.Allocator) ParseArgsError!Config {
    // Values for the configuration.
    var config = Config.init(allocator);
    errdefer config.deinit();

    // Prepare the iterator for the arguments.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = arena.allocator();
    defer arena.deinit();
    var iter = std.process.argsWithAllocator(alloc) catch unreachable;
    defer iter.deinit();
    _ = iter.next(); // Skip the name of the program.

    while (iter.next()) |arg| {
        if (argIsHelp(arg)) {
            return error.WantsHelp;
        } else if (argIsThreads(arg)) {
            // Set the threads.
            config.threads = try parseNumericArg(
                &iter, 
                error.ThreadOptionExpectsArgument, 
                error.ThreadOptionExpectsInteger);
        } else if (argIsChunk(arg)) {
            // Set the chunks.
            config.chunks_size = try parseNumericArg(
                &iter, 
                error.ChunksSizeOptionExpectsArgument, 
                error.ChunksSizeOptionExpectsInteger);
        } else {
            // Set the name of the file.
            config.input_paths.append(arg) catch std.process.exit(1);
        }
    }

    if (config.input_paths.items.len == 0) {
        return error.FilePathNotProvided;
    }
    return config;
}

fn argIsHelp(arg: []const u8) bool {
    return mem.eql(u8, arg, HELP_LONG_FLAG) or mem.eql(u8, arg, HELP_SHORT_FLAG);
}

fn argIsThreads(arg: []const u8) bool {
    return mem.eql(u8, arg, THREADS_LONG_FLAG) or mem.eql(u8, arg, THREADS_SHORT_FLAG);
}

fn argIsChunk(arg: []const u8) bool {
    return mem.eql(u8, arg, CHUNKS_LONG_FLAG) or mem.eql(u8, arg, CHUNKS_SHORT_FLAG);
}

fn parseNumericArg(
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
