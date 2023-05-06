const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const os = std.os;
const args = @import("./args.zig");
const lines = @import("./lines.zig");
const source = @import("./source.zig");

pub fn main() !void {
    var out_buffer: [100]u8 = undefined;
    const realpath = try fs.Dir.realpath(fs.cwd(), ".", &out_buffer);
    try source.main(realpath);
    if (false) {
        lines_main();
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
