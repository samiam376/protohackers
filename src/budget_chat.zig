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
