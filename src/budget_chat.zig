const std = @import("std");

const intro_msg = "Welcome to budgetchat! What shall I call you?\n";

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
        return .{ .allocator = allocator, .mutex = .{}, .connections = std.StringHashMap(std.net.Server.Connection).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.connections.deinit();
    }

    pub fn add_member(self: *Self, name: []const u8, connection: std.net.Server.Connection) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.connections.put(name, connection);
    }

    pub fn has_member(self: *Self, name: []const u8) bool {
        if (self.connections.get(name)) |_| {
            return true;
        }
        return false;
    }

    pub fn rm_member(self: *Self, name: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.connections.remove(name);
    }

    pub fn get_member_names(self: *Self) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var names = std.ArrayList([]const u8).init(self.allocator);
        var iterator = self.connections.keyIterator();
        while (iterator.next()) |name| {
            try names.append(name.*);
        }

        return try names.toOwnedSlice();
    }

    pub fn send_message(self: *Self, sender_name: []const u8, msg: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            if (!std.mem.eql(u8, entry.key_ptr.*, sender_name)) {
                try entry.value_ptr.stream.writeAll(msg);
            }
        }
    }
};

const Members = std.StringHashMap(std.net.Server.Connection);

const DELIM = '\n';
const MIN_NAME_LEN = 16;
const MAX_SIZE = 1000;

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection, chat_room: *ChatRoom) !void {
    std.log.info("Handling connection from {}\n", .{conn.address});
    defer conn.stream.close();
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();

    try writer.writeAll(intro_msg);
    var nameBuffer = std.ArrayList(u8).init(allocator);
    reader.readUntilDelimiterArrayList(&nameBuffer, DELIM, MAX_SIZE) catch |err| {
        if (err == error.EndOfStream) {
            std.log.info("Connection closed by {}\n", .{conn.address});
            return;
        }

        std.log.err("Error reading from stream: {}", .{err});
        return;
    };

    const name = try nameBuffer.toOwnedSlice();
    defer allocator.free(name);

    if (chat_room.has_member(name)) {
        std.log.info("name taken", .{});
        try writer.writeAll("Name already taken\n");
        return;
    }

    const members = try chat_room.get_member_names();
    try chat_room.add_member(name, conn);

    const user_joins = try user_joins_msg(allocator, name);
    try chat_room.send_message(name, user_joins);

    const presence = try announce_names_msg(allocator, members);
    try conn.stream.writeAll(presence);

    while (true) {
        var user_input = std.ArrayList(u8).init(allocator);
        defer user_input.deinit();
        reader.readUntilDelimiterArrayList(&user_input, DELIM, MAX_SIZE) catch |err| {
            if (err == error.EndOfStream) {
                std.log.info("Connection closed by {}\n", .{conn.address});
                break;
            }

            std.log.err("Error reading from stream: {}", .{err});
            break;
        };

        const msg = try fmt_msg(allocator, name, try user_input.toOwnedSlice());
        defer allocator.free(msg);
        try chat_room.send_message(name, msg);
    }

    chat_room.rm_member(name);
    const msg = try user_leaves_msg(allocator, name);
    try chat_room.send_message(name, msg);
}

pub fn run(allocator: std.mem.Allocator, addr: []const u8, port: u16) !void {
    var chat_room = ChatRoom.init(allocator);
    defer chat_room.deinit();

    const address = try std.net.Address.parseIp(addr, port);
    var server = try address.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 128, .force_nonblocking = false });
    defer server.deinit();
    std.log.info("listening on {}\n", .{address});

    while (true) {
        const conn = try server.accept();
        std.log.info("New connection from {}\n", .{conn.address});
        const thread = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn, &chat_room });
        thread.detach();
    }
}
