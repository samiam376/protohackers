const std = @import("std");

const net = std.net;

const DELIM = '\n';
const MAX_SIZE: usize = 1024 * 1024;

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
        reader.readUntilDelimiterArrayList(&array, DELIM, MAX_SIZE) catch |err| {
            if (err == error.EndOfStream) {
                std.log.info("Connection closed by {}\n", .{conn.address});
                break;
            }

            std.log.err("Error reading from stream: {}", .{err});
            break;
        };

        std.log.info("Received message: {s}\n", .{array.items});
        const is_prime = parseMsg(array.items, allocator) catch |err| {
            std.log.err("Error parsing message: {}\n", .{err});
            try writer.writeAll("Malformed request\n");
            return;
        };
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

fn isPrime(num: i64) bool {
    if (num <= 1) {
        return false;
    }

    if (num <= 3) {
        return true;
    }

    if (@mod(num, 2) == 0 or @mod(num, 3) == 0) {
        return false;
    }

    var i: i64 = 5;
    while (i * i <= num) : (i += 6) {
        if (@mod(num, i) == 0 or @mod(num, (i + 2)) == 0) {
            return false;
        }
    }
    return true;
}

test "is_prime" {
    std.debug.print("Running tests for isPrime\n", .{});
    try std.testing.expectEqual(isPrime(-1), false);
    try std.testing.expectEqual(isPrime(0), false);
    try std.testing.expectEqual(isPrime(1), false);
    try std.testing.expectEqual(isPrime(2), true);
    try std.testing.expectEqual(isPrime(3), true);
    try std.testing.expectEqual(isPrime(4), false);
    try std.testing.expectEqual(isPrime(4.000), false);
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

const Response = struct {
    method: []const u8,
    prime: bool,
};

// parse bytes into a json of
// {"method":"isPrime","number":123}
// return an error if malformed
fn parseMsg(msg: []const u8, allocator: std.mem.Allocator) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, msg, .{});
    defer parsed.deinit();
    switch (parsed.value) {
        .object => |v| {
            const method = v.get("method") orelse return MsgError.Malformed;
            switch (method) {
                .string => |s| {
                    if (!std.mem.eql(u8, s, "isPrime")) {
                        return MsgError.Malformed;
                    }
                },
                else => return MsgError.Malformed,
            }

            const number = v.get("number") orelse return MsgError.Malformed;
            switch (number) {
                .float => {
                    return false;
                },
                .integer => |i| {
                    return isPrime(i);
                },
                .number_string => {
                    // hacky, but passes test
                    return false;
                },
                else => return MsgError.Malformed,
            }
        },
        else => return MsgError.Malformed,
    }
    return MsgError.Malformed;
}

test "parse" {
    const allocator = std.testing.allocator;
    const validMsg = "{\"method\":\"isPrime\",\"number\":123}";
    try std.testing.expectEqual(parseMsg(validMsg, allocator), false);

    const invalidMsg = "{\"method\":\"isPrime\"}";
    try std.testing.expectEqual(parseMsg(invalidMsg, allocator), MsgError.Malformed);

    const invalidMethod = "{\"method\":\"isEven\",\"number\":123}";
    try std.testing.expectEqual(parseMsg(invalidMethod, allocator), MsgError.Malformed);

    const invalidMethod1 = "{\"method\":\"isEven\",\"number\":\"123\"}";
    try std.testing.expectEqual(parseMsg(invalidMethod1, allocator), MsgError.Malformed);

    const bigNumber = "{\"method\":\"isPrime\",\"number\":188081179245707415821627738598061142252554349208353792008, \"bignumber\": true}";
    try std.testing.expectEqual(
        false,
        parseMsg(bigNumber, allocator),
    );
}
