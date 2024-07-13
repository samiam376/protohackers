const std = @import("std");

const Insert = struct { timestamp: i32, price: i32 };

const Query = struct { mintime: i32, maxtime: i32 };

const ParseError = error{ InvalidNumBytes, InvalidLeadingChar };

const ParseResponse = union(enum) { insert: Insert, query: Query };

fn parseMsg(bytes: []const u8) ParseError!ParseResponse {
    if (bytes.len != 9) {
        return ParseError.InvalidNumBytes;
    }
    const leading = bytes[0];
    if (leading == 'I') {
        const timestamp = std.mem.readInt(i32, bytes[1..5], std.builtin.Endian.big);
        const price = std.mem.readInt(i32, bytes[5..9], std.builtin.Endian.big);
        return .{ .insert = .{ .timestamp = timestamp, .price = price } };
    } else if (leading == 'Q') {
        const mintime = std.mem.readInt(i32, bytes[1..5], std.builtin.Endian.big);
        const maxtime = std.mem.readInt(i32, bytes[5..9], std.builtin.Endian.big);
        return .{ .query = .{ .maxtime = maxtime, .mintime = mintime } };
    } else {
        std.debug.print("Invalid Leading Char. Received: {}\n", .{leading});
        return ParseError.InvalidLeadingChar;
    }
}

test "parseMsg" {
    std.debug.print("Testing Parse Msg", .{});
    const query = [9]u8{ 0x51, 0x00, 0x00, 0x03, 0xE8, 0x00, 0x01, 0x86, 0xA0 };
    const parsedQuery = try parseMsg(&query);
    const expectedQuery = ParseResponse{ .query = .{ .mintime = 1000, .maxtime = 100000 } };
    try std.testing.expectEqualDeep(expectedQuery, parsedQuery);

    const insert = [9]u8{ 0x49, 0x00, 0x00, 0x30, 0x39, 0x00, 0x00, 0x00, 0x65 };
    const parsedInsert = try parseMsg(&insert);
    const expectedInsert = ParseResponse{
        .insert = .{ .timestamp = 12345, .price = 101 },
    };
    try std.testing.expectEqualDeep(expectedInsert, parsedInsert);
}

const Price = struct {
    cents: i32,
    timestamp: i32,
};

const AssetPricing = struct {
    prices: std.ArrayList(Price),

    pub fn init(allocator: std.mem.Allocator) AssetPricing {
        return AssetPricing{ .prices = std.ArrayList(Price).init(allocator) };
    }

    pub fn deinit(self: *AssetPricing) void {
        self.prices.deinit();
    }

    pub fn insert(self: *AssetPricing, price: Price) !void {
        try self.prices.append(price);
    }

    pub fn avg(a: AssetPricing, lb: i32, ub: i32) i32 {
        if (lb > ub) {
            return 0;
        }

        var acc: i64 = 0;
        var count: u32 = 0;

        for (a.prices.items) |p| {
            if (lb <= p.timestamp and p.timestamp <= ub) {
                count += 1;
                acc += p.cents;
            }
        }

        if (count == 0) {
            return 0;
        }

        const mean: i32 = @intCast(@divFloor(acc, count));
        return mean;
    }
};

test "pricing" {
    const allocator = std.testing.allocator;
    var ap = AssetPricing.init(allocator);
    defer ap.deinit();
    try ap.insert(.{ .timestamp = 12345, .cents = 101 });
    try ap.insert(.{ .timestamp = 12346, .cents = 102 });
    try ap.insert(.{ .timestamp = 12347, .cents = 100 });
    try ap.insert(.{ .timestamp = 40960, .cents = 5 });

    const avg = ap.avg(12288, 16384);
    try std.testing.expectEqual(101, avg);
}

const MSG_LEN = 9;

fn handleConnection(conn: std.net.Server.Connection) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();

    var pricing = AssetPricing.init(allocator);
    defer pricing.deinit();

    while (true) {
        const msg_raw = try reader.readBoundedBytes(MSG_LEN);
        if (msg_raw.len == 0) {
            std.log.info("End of stream reached\n", .{});
            return;
        }
        std.log.info("handling msg: {}\n", .{msg_raw});
        const msg = try parseMsg(msg_raw.constSlice());
        std.log.info("parsed: {}\n", .{msg});

        switch (msg) {
            .query => |q| {
                const avg = pricing.avg(q.mintime, q.maxtime);
                std.log.info("calculated avg: {}\n", .{avg});
                try writer.writeInt(i32, avg, std.builtin.Endian.big);
            },
            .insert => |i| {
                try pricing.insert(.{ .cents = i.price, .timestamp = i.timestamp });
            },
        }
    }
}

pub fn run(addr: []const u8, port: u16) !void {
    const address = try std.net.Address.parseIp(addr, port);
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
