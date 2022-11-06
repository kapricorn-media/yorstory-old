const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");

pub const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    pub fn init(url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !Self
    {
        _ = priority;
        const texture = w.loadTexture(&url[0], url.len, wrapMode, filter);
        if (texture == -1) {
            return error.createTextureFailed;
        }

        return Self {
            .id = texture,
            .size = m.Vec2i.zero, // set later when the image is loaded from URL
        };
    }

    pub fn loaded(self: Self) bool
    {
        return !m.Vec2i.eql(self.size, m.Vec2i.zero);
    }
};

// pub const TextureId = union {
// };

pub fn Assets(comptime StaticTextureEnum: type, comptime maxDynamicTextures: usize) type
{
    const T = struct {
        const numStaticTextures = @typeInfo(StaticTextureEnum).Enum.fields.len;

        staticTextures: [numStaticTextures]TextureData,
        numDynamicTextures: usize,
        dynamicTextures: [maxDynamicTextures]TextureData,
        idMap: std.StringHashMap(usize),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self
        {
            return Self {
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

        pub fn getDynamicTextureData(self: Self, id: usize) ?TextureData
        {
            if (id >= self.numDynamicTextures) {
                return null;
            }
            return self.dynamicTextures[id];
        }

        pub fn getDynamicTextureDataUri(self: Self, uri: []const u8) ?TextureData
        {
            const id = self.idMap.get(uri) orelse return null;
            return self.getDynamicTextureData(id);
        }

        // pub fn registerStaticTexture(self: *Self, texture: StaticTextureEnum, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !usize
        // {
        // }

        pub fn registerDynamicTexture(self: *Self, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !usize
        {
            if (self.numDynamicTextures >= self.dynamicTextures.len) {
                return error.FullDynamicTextures;
            }

            const id = self.numDynamicTextures;
            self.dynamicTextures[id] = try TextureData.init(url, wrapMode, filter, priority);

            try self.idMap.put(url, id);

            self.numDynamicTextures += 1;
            return id;
        }
    };

    return T;
}
