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
