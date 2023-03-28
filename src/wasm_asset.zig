const std = @import("std");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

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

pub const FontCharData = struct {
    offset: m.Vec2,
    size: m.Vec2,
    uvOffset: m.Vec2,
    advanceX: f32,
};

pub const FontLoadData = struct {
    size: f32,
    scale: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn load(self: *Self, atlasSize: usize, fontFileData: []const u8, size: f32, scale: f32, allocator: std.mem.Allocator) ![]const u8
    {
        var tempArena = std.heap.ArenaAllocator.init(allocator);
        defer tempArena.deinit();
        const tempAllocator = tempArena.allocator();

        self.size = size;
        self.scale = scale;

        const width = atlasSize;
        const height = atlasSize;
        var pixelBytes = try allocator.alloc(u8, width * height);
        std.mem.set(u8, pixelBytes, 0);
        var context: stb.stbtt_pack_context = undefined;
        const constCasted = @intToPtr(*std.mem.Allocator, @ptrToInt(&tempAllocator)); // TODO hacky
        if (stb.stbtt_PackBegin(&context, &pixelBytes[0], @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, width), 1, constCasted) != 1) {
            return error.stbtt_PackBegin;
        }
        const oversampleN = 1;
        stb.stbtt_PackSetOversampling(&context, oversampleN, oversampleN);

        var charData = try allocator.alloc(stb.stbtt_packedchar, self.charData.len);
        if (stb.stbtt_PackFontRange(&context, &fontFileData[0], 0, size / scale, 0, @intCast(c_int, charData.len), &charData[0]) != 1) {
            return error.stbtt_PackFontRange;
        }

        stb.stbtt_PackEnd(&context);

        for (charData) |cd, i| {
            const sizeF = m.Vec2.initFromVec2i(m.Vec2i.init(cd.x1 - cd.x0, cd.y1 - cd.y0));
            self.charData[i] = FontCharData {
                .offset = m.Vec2.init(cd.xoff, -(sizeF.y + cd.yoff)),
                .size = sizeF,
                .uvOffset = m.Vec2.init(
                    @intToFloat(f32, cd.x0) / @intToFloat(f32, width),
                    @intToFloat(f32, height - cd.y1) / @intToFloat(f32, height), // TODO should do -1 ?
                ),
                .advanceX = cd.xadvance,
            };
        }

        return pixelBytes;
    }
};

pub const FontData = struct {
    loaded: bool,
    textureId: c_uint,
    size: f32,
    scale: f32,
    kerning: f32,
    lineHeight: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn load(self: *Self, fontUrl: []const u8, size: f32, scale: f32, kerning: f32, lineHeight: f32) !void
    {
        const atlasSize = 4096;
        if (self.loaded) {
            self.loaded = false;
        }
        self.textureId = w.loadFontDataJs(&fontUrl[0], fontUrl.len, size, scale, atlasSize);
        self.size = size;
        self.scale = scale;
        self.kerning = kerning;
        self.lineHeight = lineHeight;
    }

    pub fn writeFontLoadData(self: *Self, fontLoadData: *const FontLoadData) !void
    {
        if (self.size != fontLoadData.size) {
            return error.FontSizeMismatch;
        }
        std.mem.copy(FontCharData, &self.charData, &fontLoadData.charData);
        self.loaded = true;
    }
};

pub fn Assets(comptime StaticTextureEnum: type, comptime maxDynamicTextures: usize, comptime StaticFontEnum: type) type
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

        const numStaticFonts = @typeInfo(StaticFontEnum).Enum.fields.len;

        allocator: std.mem.Allocator,
        staticTextures: [numStaticTextures]TextureData,
        // TODO use BoundedArray?
        dynamicTexturesSize: usize,
        dynamicTextures: [maxDynamicTextures]TextureData,
        textureLoadQueueSize: usize,
        textureLoadQueue: [maxTotalTextures]TextureLoadEntry,
        textureInflight: usize,
        textureIdMap: std.StringHashMap(usize),
        staticFonts: [numStaticFonts]FontData,

        const Self = @This();

        fn getDynamicTextures(self: *Self) []TextureData
        {
            return self.dynamicTextures[0..self.dynamicTexturesSize];
        }

        fn getDynamicTexturesConst(self: *const Self) []const TextureData
        {
            return self.dynamicTextures[0..self.dynamicTexturesSize];
        }

        fn getDynamicTextureData(self: *const Self, id: usize) ?*const TextureData
        {
            if (id >= self.dynamicTexturesSize) {
                return null;
            }
            return &self.dynamicTextures[id];
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
            try self.textureIdMap.put(urlCopy, id);

            self.dynamicTexturesSize += 1;
            return id;
        }

        fn addLoadEntry(self: *Self, id: c_uint, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !void
        {
            if (self.textureLoadQueueSize >= self.textureLoadQueue.len) {
                return error.FullLoadQueue;
            }

            self.textureLoadQueue[self.textureLoadQueueSize] = TextureLoadEntry {
                .id = id,
                .url = url,
                .wrapMode = wrapMode,
                .filter = filter,
                .priority = priority,
            };
            self.textureLoadQueueSize += 1;
        }

        pub fn load(self: *Self, allocator: std.mem.Allocator) void
        {
            const nullTextureId = 99969; // 0 is a valid texture ID, so init to something big

            for (self.staticTextures) |*t| {
                t.id = nullTextureId; 
            }
            self.allocator = allocator;
            self.dynamicTexturesSize = 0;
            self.textureLoadQueueSize = 0;
            self.textureInflight = 0;
            self.textureIdMap = std.StringHashMap(usize).init(allocator);

            for (self.staticFonts) |*f| {
                f.loaded = false;
                f.textureId = nullTextureId;
            }
        }

        pub fn getStaticTextureData(self: *const Self, texture: StaticTextureEnum) *const TextureData
        {
            return &self.staticTextures[@enumToInt(texture)];
        }

        pub fn getTextureData(self: *const Self, id: TextureId) ?*const TextureData
        {
            switch (id) {
                .Static => |t| return self.getStaticTextureData(t),
                .DynamicId => |theId| return self.getDynamicTextureData(theId),
                .DynamicUrl => |url| {
                    const theId = self.textureIdMap.get(url) orelse return null;
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

        pub fn loadQueued(self: *Self, maxInflight: usize) void
        {
            if (self.textureLoadQueueSize == 0) {
                return;
            }

            const textureInflight = self.textureInflight;
            const maxToAddInflight = if (maxInflight >= textureInflight) maxInflight - textureInflight else 0;
            const numToLoad = std.math.min(maxToAddInflight, self.textureLoadQueueSize);

            var i: usize = 0;
            while (i < numToLoad) : (i += 1) {
                var entryIndex: usize = 0;
                var j: usize = 1;
                while (j < self.textureLoadQueueSize) : (j += 1) {
                    if (self.textureLoadQueue[j].priority < self.textureLoadQueue[entryIndex].priority) {
                        entryIndex = j;
                    }
                }

                const entry = self.textureLoadQueue[entryIndex];
                w.loadTexture(entry.id, &entry.url[0], entry.url.len, entry.wrapMode, entry.filter);
                self.textureInflight += 1;
                self.textureLoadQueue[entryIndex] = self.textureLoadQueue[self.textureLoadQueueSize - 1];
                self.textureLoadQueueSize -= 1;
            }
        }

        pub fn onTextureLoaded(self: *Self, id: c_uint, size: m.Vec2i) !void
        {
            var found = false;
            for (self.staticTextures) |*texture| {
                if (texture.id == id) {
                    texture.size = size;
                    found = true;
                    break;
                }
            }

            for (self.getDynamicTextures()) |*texture| {
                if (texture.id == id) {
                    texture.size = size;
                    found = true;
                    break;
                }
            }

            self.textureInflight -= 1;

            if (!found) {
                return error.TextureNotFound;
            }
        }

        pub fn registerStaticFont(self: *Self, font: StaticFontEnum, fontUrl: []const u8, size: f32, scale: f32, kerning: f32, lineHeight: f32) !void
        {
            // TODO auto-scale to fit in font atlas
            const maxSize = 256.0;
            var newScale = scale;
            while ((size / newScale) >= maxSize) {
                newScale *= 2.0;
            }
            try self.staticFonts[@enumToInt(font)].load(fontUrl, size, newScale, kerning, lineHeight);
        }

        pub fn getStaticFontData(self: *const Self, font: StaticFontEnum) ?*const FontData
        {
            const f = &self.staticFonts[@enumToInt(font)];
            return if (f.loaded) f else null;
        }

        pub fn onFontLoaded(self: *Self, atlasTextureId: c_uint, fontLoadData: *const FontLoadData) !void
        {
            var found = false;
            for (self.staticFonts) |*font| {
                if (font.textureId == atlasTextureId) {
                    try font.writeFontLoadData(fontLoadData);
                    found = true;
                    break;
                }
            }
        }
    };

    return T;
}
