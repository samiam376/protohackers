const std = @import("std");
const net = std.net;

fn handleConnection(conn: std.net.Server.Connection) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();

    while (true) {
        const bytes_read = reader.read(&buf) catch |err| {
            std.log.err("Error reading from {}: {}\n", .{ conn.address, err });
            return;
        };

        if (bytes_read == 0) {
            std.log.info("client disconnected\n", .{});
            return;
        }
        std.log.info("Read {} bytes from {}\n", .{ bytes_read, conn.address });
        writer.writeAll(buf[0..bytes_read]) catch |err| {
            std.log.err("Error writing to {}: {}\n", .{ conn.address, err });
            return;
        };
        std.log.info("Wrote {} bytes to {}\n", .{ bytes_read, conn.address });
    }
}

pub fn run(addr: []const u8, port: u16) !void {
    const address = try net.Address.parseIp(addr, port);
    var server = try address.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 128, .force_nonblocking = false });
    defer server.deinit();
    std.log.info("listening on {}\n", .{address});
    while (true) {
        const conn = try server.accept();
        std.log.info("New connection from {}\n", .{conn.address});
        const thread = try std.Thread.spawn(.{}, handleConnection, .{conn});
        thread.detach();
    }
}
