const std = @import("std");

const m = @import("zigkm-math");

pub const Section = struct {
    name: []const u8,
    description: []const u8,
    images: []const []const u8,
};

pub const Project = struct {
    name: []const u8,
    company: []const u8,
    uri: []const u8,
    cover: []const u8,
    sticker: []const u8,
    parallaxIndex: usize,
    colorUi: m.Vec4,
    colorSticker: m.Vec4,
    youtubeId: ?[]const u8,
    contentHeader: []const u8,
    contentDescription: []const u8,
    sections: []const Section,
};

pub const Portfolio = struct {
    projects: []const Project,

    const Self = @This();

    pub fn init(json: []const u8, allocator: std.mem.Allocator) !Self
    {
        var tokenStream = std.json.TokenStream.init(json);
        return std.json.parse(Portfolio, &tokenStream, .{.allocator = allocator});
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void
    {
        std.json.parseFree(Portfolio, self.*, .{.allocator = allocator});
    }
};
