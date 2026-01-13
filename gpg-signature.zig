const std = @import("std");
const max_size = 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const input_path = "index.html";
    const content = try std.fs.cwd().readFileAlloc(allocator, input_path, max_size);

    const parts = try splitHtml(content);

    const signed_body = try gpgSign(allocator, parts.body);

    const output_file = try std.fs.cwd().createFile("index.html", .{});
    defer output_file.close();

    var output_buffer: [1024]u8 = undefined;

    var output_writer = output_file.writer(&output_buffer);
    const writer = &output_writer.interface;

    try writer.writeAll(parts.prefix);
    try writer.writeAll(signed_body);
    try writer.writeAll(parts.suffix);
    try writer.flush();
}

const HtmlParts = struct {
    prefix: []const u8,
    body: []const u8,
    suffix: []const u8,
};

fn splitHtml(content: []const u8) !HtmlParts {
    const pre_tag = "<pr";
    const pre_close_tag = "</pr";

    const first_pre_start = std.mem.indexOfPosLinear(u8, content, 0, pre_tag).?;
    const first_pre_end = std.mem.indexOfScalarPos(u8, content, first_pre_start, '>').? + 2;

    const first_close_start = std.mem.indexOfPosLinear(u8, content, first_pre_end, pre_close_tag).?;
    const last_pre_start = std.mem.lastIndexOfLinear(u8, content[first_close_start..], pre_tag).? + first_close_start;
    const last_pre_end = std.mem.indexOfScalarPos(u8, content, last_pre_start, '>').?;
    const last_close_start = std.mem.indexOfPosLinear(u8, content, last_pre_end, pre_close_tag).?;

    return HtmlParts{
        .prefix = content[0..first_pre_end],
        .body = content[first_close_start .. last_pre_end + 1],
        .suffix = content[last_close_start..],
    };
}

fn gpgSign(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const argv = [_][]const u8{ "gpg", "--clearsign", "-" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdin_file = child.stdin.?;
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_writer = stdin_file.writer(&stdin_buffer);
    const stdin = &stdin_writer.interface;

    try stdin.writeAll(input);
    try stdin.flush();
    stdin_file.close();
    child.stdin = null;

    var stdout_buffer: std.ArrayList(u8) = .empty;
    var stderr_buffer: std.ArrayList(u8) = .empty;

    try child.collectOutput(allocator, &stdout_buffer, &stderr_buffer, max_size);

    const term = try child.wait();
    if (term != .Exited) {
        std.debug.print("GPG Error: {s}\n", .{stderr_buffer.items});
        return error.GpgFailed;
    }

    return stdout_buffer.items;
}
