const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const os = std.os;
const args = @import("./args.zig");
const lines = @import("./lines.zig");
const source = @import("./source.zig");
const Runner = @import("./runner.zig").Runner;

pub fn main() !void {
    var runner = Runner{};
    try runner.run();
}
