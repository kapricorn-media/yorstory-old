const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");

pub const TextureLoadEntry = struct {
    id: c_uint,
    url: []const u8,
    wrapMode: c_uint,
    filter: c_uint,
    priority: u32,
};

pub const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    pub fn init() Self
    {
        return Self {
            .id = w.glCreateTexture(),
            .size = m.Vec2i.zero,
        };
    }

    pub fn loaded(self: Self) bool
    {
        return !m.Vec2i.eql(self.size, m.Vec2i.zero);
    }
};

pub fn Assets(comptime StaticTextureEnum: type, comptime maxDynamicTextures: usize) type
{
    const TextureIdType = enum {
        Static,
        DynamicId,
        DynamicUrl,
    };
    const TextureId = union(TextureIdType) {
        Static: StaticTextureEnum,
        DynamicId: usize,
        DynamicUrl: []const u8,
    };

    const T = struct {
        const numStaticTextures = @typeInfo(StaticTextureEnum).Enum.fields.len;
        const maxTotalTextures = numStaticTextures + maxDynamicTextures;

        allocator: std.mem.Allocator,
        staticTextures: [numStaticTextures]TextureData,
        dynamicTexturesSize: usize,
        dynamicTextures: [maxDynamicTextures]TextureData,
        loadQueueSize: usize,
        loadQueue: [maxTotalTextures]TextureLoadEntry,
        idMap: std.StringHashMap(usize),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self
        {
            return Self {
                .allocator = allocator,
                .staticTextures = undefined,
                .dynamicTexturesSize = 0,
                .dynamicTextures = undefined,
                .loadQueueSize = 0,
                .loadQueue = undefined,
                .idMap = std.StringHashMap(usize).init(allocator),
            };
        }

        pub fn getStaticTextureData(self: Self, texture: StaticTextureEnum) TextureData
        {
            return self.staticTextures[@enumToInt(texture)];
        }

        fn getDynamicTextureData(self: Self, id: usize) ?TextureData
        {
            if (id >= self.dynamicTexturesSize) {
                return null;
            }
            return self.dynamicTextures[id];
        }

        fn registerStaticTexture(self: *Self, texture: StaticTextureEnum, textureData: TextureData) !void
        {
            self.staticTextures[@enumToInt(texture)] = textureData;
        }

        fn registerDynamicTexture(self: *Self, url: []const u8, textureData: TextureData) !usize
        {
            if (self.dynamicTexturesSize >= self.dynamicTextures.len) {
                return error.FullDynamicTextures;
            }

            const id = self.dynamicTexturesSize;
            self.dynamicTextures[id] = textureData;

            const urlCopy = try self.allocator.dupe(u8, url);
            try self.idMap.put(urlCopy, id);

            self.dynamicTexturesSize += 1;
            return id;
        }

        fn addLoadEntry(self: *Self, id: c_uint, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !void
        {
            if (self.loadQueueSize >= self.loadQueue.len) {
                return error.FullLoadQueue;
            }

            self.loadQueue[self.loadQueueSize] = TextureLoadEntry {
                .id = id,
                .url = url,
                .wrapMode = wrapMode,
                .filter = filter,
                .priority = priority,
            };
            self.loadQueueSize += 1;
        }

        pub fn getTextureData(self: Self, id: TextureId) ?TextureData
        {
            switch (id) {
                .Static => |t| return self.getStaticTextureData(t),
                .DynamicId => |theId| return self.getDynamicTextureData(theId),
                .DynamicUrl => |url| {
                    const theId = self.idMap.get(url) orelse return null;
                    return self.getDynamicTextureData(theId);
                },
            }
        }

        pub fn register(self: *Self, id: TextureId, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !usize
        {
            const data = TextureData.init();
            try self.addLoadEntry(data.id, url, wrapMode, filter, priority);
            switch (id) {
                .Static => |t| {
                    try self.registerStaticTexture(t, data);
                    return @intCast(usize, 0);
                },
                .DynamicId => |_| {
                    return self.registerDynamicTexture(url, data);
                },
                .DynamicUrl => |_| {
                    return self.registerDynamicTexture(url, data);
                },
            }
        }

        pub fn loadQueued(self: *Self) void
        {
            std.log.info("size {}", .{self.loadQueueSize});
            for (self.loadQueue[0..self.loadQueueSize]) |entry| {
                w.loadTexture(entry.id, &entry.url[0], entry.url.len, entry.wrapMode, entry.filter);
            }
            self.loadQueueSize = 0;
        }
    };

    return T;
}
