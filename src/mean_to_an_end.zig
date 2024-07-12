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

    pub fn new(allocator: std.mem.Allocator) AssetPricing {
        return AssetPricing{ .prices = std.ArrayList(Price).init(allocator) };
    }

    pub fn deinit(self: *AssetPricing) void {
        self.prices.deinit();
    }

    pub fn avg(a: AssetPricing, lb: i32, ub: i32) i32 {
        if (lb > ub) {
            return 0;
        }

        var acc: i32 = 0;
        const len: i32 = @intCast(a.prices.items.len);

        if (!len) {
            return 0;
        }

        for (a.prices.items) |p| {
            if (lb <= p.timestamp and p.timestamp <= ub) {
                acc += p.cents;
            }
        }

        const mean = acc / len;
        return mean;
    }
};
