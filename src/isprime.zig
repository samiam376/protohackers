const std = @import("std");
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
