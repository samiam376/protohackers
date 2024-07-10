const std = @import("std");
const net = std.net;
const smoketest = @import("smoketest.zig");

const Args = struct {
    addr: []const u8,
    port: u16,
};

fn parseArgs(args: *std.process.ArgIterator) !Args {
    _ = args.next();
    var addr: []const u8 = "127.0.0.1";
    var port: u16 = 9000;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--addr")) {
            if (args.next()) |tmp| {
                addr = tmp;
            }
        } else if (std.mem.eql(u8, arg, "--port")) {
            if (args.next()) |tmp| {
                port = try std.fmt.parseInt(u16, tmp, 10);
            }
        } else {
            continue;
        }
    }
    return Args{ .addr = addr, .port = port };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    const parsed = try parseArgs(&args);
    //parse from args and fallback to default values
    const addr = parsed.addr;
    const port = parsed.port;

    try smoketest.run(addr, port);
}
