const std = @import("std");
const net = std.net;

pub fn main() !void {
    const address = try net.Address.parseIp("127.0.0.1", 9000);
    var server = try address.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 128, .force_nonblocking = false });
    // var server = net.d;
    defer server.deinit();
    std.log.info("listening on {}\n", .{address});
    while (true) {
        const conn = try server.accept();
        std.log.info("New connection from {}\n", .{conn.address});
        const thread = try std.Thread.spawn(.{}, handleConnection, .{conn});
        thread.detach();
    }
}

fn handleConnection(conn: std.net.Server.Connection) !void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    var stream = std.io.bufferedReader(conn.stream.reader());
    var reader = stream.reader();
    var writer = conn.stream.writer();

    while (true) {
        const bytes_read = try reader.read(&buf);
        if (bytes_read == 0) {
            std.log.info("client disconnected\n", .{});
            return;
        }
        std.log.info("Read {} bytes from {}\n", .{ bytes_read, conn.address });
        const bytes_written = try writer.writeAll(buf[0..bytes_read]);
        std.log.info("Wrote {} bytes to {}\n", .{ bytes_written, conn.address });
    }
}
