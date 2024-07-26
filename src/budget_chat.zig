const std = @import("std");

const intro_msg = "Welcome to budgetchat! What shall I call you?";

fn announce_names_msg(allocator: std.mem.Allocator, names: []const []const u8) ![]u8 {
    const names_string = try std.mem.join(allocator, ", ", names);
    defer allocator.free(names_string);
    const result = try std.fmt.allocPrint(allocator, "* The room contains: {s}\n", .{names_string});
    return result;
}

test "announce_names_msg" {
    const allocator = std.testing.allocator;
    const names = &[_][]const u8{ "Finn", "Franklin", "Filip" };
    const msg = try announce_names_msg(allocator, names);
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("* The room contains: Finn, Franklin, Filip\n", msg);
}

fn user_joins_msg(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "* {s} has entered the room\n", .{name});
    return msg;
}

test "user_join_msg" {
    const allocator = std.testing.allocator;
    const msg = try user_joins_msg(allocator, "Bob");
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("* Bob has entered the room\n", msg);
}

fn user_leaves_msg(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "* {s} has left the room\n", .{name});
    return msg;
}

test "user_leaves_msg" {
    const allocator = std.testing.allocator;
    const msg = try user_leaves_msg(allocator, "Bob");
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("* Bob has left the room\n", msg);
}

fn fmt_msg(allocator: std.mem.Allocator, user_name: []const u8, msg: []const u8) ![]u8 {
    const result = try std.fmt.allocPrint(allocator, "[{s}] {s}\n", .{ user_name, msg });
    return result;
}

test "fmt_msg" {
    const allocator = std.testing.allocator;
    const msg = try fmt_msg(allocator, "Alice", "Hello, World!");
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("[Alice] Hello, World!\n", msg);
}

const ChatRoom = struct {
    connections: std.StringHashMap(std.net.Server.Connection),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator, .mutex = .{}, .connections = std.StringHashMap(std.StringHashMap(std.net.Server.Connection)).init() };
    }

    pub fn deinit(self: *Self) void {
        self.connections.deinit();
    }

    pub fn presence_notification(self: *Self, target_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const connection = self.connections.get(target_name);
        if (connection) |conn| {
            var names = std.ArrayList([]u8).init(self.allocator);
            for (self.connections.keyIterator().items) |name| {
                if (!std.mem.eql(u8, target_name, name)) {
                    names.append(name);
                }
            }

            const msg = try announce_names_msg(self.allocator, try names.toOwnedSlice());
            try conn.stream.writeAll(msg);
        }
    }
};

const Members = std.StringHashMap(std.net.Server.Connection);

const DELIM = '\n';
const MIN_NAME_LEN = 16;
const MAX_SIZE = 1000;

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection, members: *Members) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();

    try writer.writeAll(intro_msg);
    var nameBuffer = std.ArrayList(u8).init(allocator);
    defer nameBuffer.deinit();
    reader.readUntilDelimiterArrayList(&nameBuffer, DELIM, MAX_SIZE) catch |err| {
        if (err == error.EndOfStream) {
            std.log.info("Connection closed by {}\n", .{conn.address});
            return;
        }

        std.log.err("Error reading from stream: {}", .{err});
        return;
    };

    const name = try nameBuffer.toOwnedSlice();
    if (name.len < 16) {
        std.log.info("name too short", {});
        conn.stream.close();
        return;
    }
    try members.put(name, conn);
    defer {
        const removed = members.remove(name);
        std.debug.assert(removed);
    }

    // while (true) {}
}

pub fn run(allocator: std.mem.Allocator, addr: []const u8, port: u16) !void {
    var members = Members.init(allocator);
    defer members.deinit();

    const address = try std.net.Address.parseIp(addr, port);
    var server = try address.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 128, .force_nonblocking = false });
    defer server.deinit();
    std.log.info("listening on {}\n", .{address});

    while (true) {
        const conn = try server.accept();
        std.log.info("New connection from {}\n", .{conn.address});
        const thread = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn, &members });
        thread.detach();
    }
}
