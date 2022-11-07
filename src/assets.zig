const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");

pub const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    pub fn init(url: []const u8, wrapMode: c_uint, filter: c_uint) !Self
    {
        const texture = w.loadTexture(&url[0], url.len, wrapMode, filter);
        if (texture == -1) {
            return error.createTextureFailed;
        }

        return Self {
            .id = texture,
            .size = m.Vec2i.zero, // set later when the image is loaded from URL
        };
    }

    pub fn initNew() Self
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

        allocator: std.mem.Allocator,
        staticTextures: [numStaticTextures]TextureData,
        numDynamicTextures: usize,
        dynamicTextures: [maxDynamicTextures]TextureData,
        idMap: std.StringHashMap(usize),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self
        {
            return Self {
                .allocator = allocator,
                .staticTextures = undefined,
                .numDynamicTextures = 0,
                .dynamicTextures = undefined,
                .idMap = std.StringHashMap(usize).init(allocator),
            };
        }

        pub fn getStaticTextureData(self: Self, texture: StaticTextureEnum) TextureData
        {
            return self.staticTextures[@enumToInt(texture)];
        }

        fn getDynamicTextureData(self: Self, id: usize) ?TextureData
        {
            if (id >= self.numDynamicTextures) {
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
            if (self.numDynamicTextures >= self.dynamicTextures.len) {
                return error.FullDynamicTextures;
            }

            const id = self.numDynamicTextures;
            self.dynamicTextures[id] = textureData;

            const urlCopy = try self.allocator.dupe(u8, url);
            try self.idMap.put(urlCopy, id);

            self.numDynamicTextures += 1;
            return id;
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
            _ = priority;
            // const data = try TextureData.init(url, wrapMode, filter);
            const data = TextureData.initNew(); _ = url; _ = wrapMode; _ = filter;
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
    };

    return T;
}
