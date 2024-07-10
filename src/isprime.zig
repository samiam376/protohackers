const std = @import("std");

const net = std.net;

fn handleConnection(conn: std.net.Server.Connection) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();
    std.json.parseFromValue();
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

fn isPrime(num: u64) bool {
    if (num <= 1) {
        return false;
    }

    if (num <= 3) {
        return true;
    }

    if (num % 2 == 0 or num % 3 == 0) {
        return false;
    }

    var i: u64 = 5;
    while (i * i <= num) : (i += 6) {
        if (num % i == 0 or num % (i + 2) == 0) {
            return false;
        }
    }
    return true;
}

test "is_prime" {
    std.debug.print("Running tests for isPrime\n", .{});
    try std.testing.expectEqual(isPrime(1), false);
    try std.testing.expectEqual(isPrime(2), true);
    try std.testing.expectEqual(isPrime(3), true);
    try std.testing.expectEqual(isPrime(4), false);
    try std.testing.expectEqual(isPrime(5), true);
    try std.testing.expectEqual(isPrime(6), false);
    try std.testing.expectEqual(isPrime(7), true);
    try std.testing.expectEqual(isPrime(8), false);
    try std.testing.expectEqual(isPrime(9), false);
    try std.testing.expectEqual(isPrime(10), false);
    try std.testing.expectEqual(isPrime(100), false);
    try std.testing.expectEqual(isPrime(227), true);
    std.debug.print("Done\n", .{});
}

const MsgError = error{Malformed};

const Msg = struct { method: []u8, number: u64 };

// parse bytes into a json of
// {"method":"isPrime","number":123}
// return an error if malformed
fn parseMsg(msg: []const u8, allocator: std.mem.Allocator) !u64 {
    const parsed = try std.json.parseFromSlice(Msg, allocator, msg, .{});
    defer parsed.deinit();
    if (std.mem.eql(u8, parsed.value.method, "isPrime")) {
        return parsed.value.number;
    } else {
        return MsgError.Malformed;
    }
}

test "parse" {
    const allocator = std.testing.allocator;
    const validMsg = "{\"method\":\"isPrime\",\"number\":123}";
    try std.testing.expectEqual(parseMsg(validMsg, allocator), 123);

    const invalidMsg = "{\"method\":\"isPrime\"}";
    try std.testing.expectEqual(parseMsg(invalidMsg, allocator), error.MissingField);

    const invalidMethod = "{\"method\":\"isEven\",\"number\":123}";
    try std.testing.expectEqual(parseMsg(invalidMethod, allocator), MsgError.Malformed);
    }
