const std = @import("std");

const net = std.net;

const DELIM = '\n';

fn handleConnection(conn: std.net.Server.Connection) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();
    while (true) {
        var array = std.ArrayList(u8).init(allocator);
        defer array.deinit();
        reader.readUntilDelimiterArrayList(&array, DELIM, 4096) catch |err| {
            if (err == error.EndOfStream) {
                std.log.info("Connection closed by {}\n", .{conn.address});
                break;
            }

            std.log.err("Error reading from stream: {}", .{err});
            break;
        };
        const num = parseMsg(array.items, allocator) catch |err| {
            std.log.err("Error parsing message: {}\n", .{err});
            try writer.writeAll("Malformed request\n");
            return;
        };
        const is_prime = isPrime(num);
        const response = Response{ .method = "isPrime", .prime = is_prime };
        try std.json.stringify(
            response,
            .{},
            writer,
        );
        try writer.writeByte(DELIM);
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
const Response = struct {
    method: []const u8,
    prime: bool,
};

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
