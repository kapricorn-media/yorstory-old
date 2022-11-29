const std = @import("std");

const assets = @import("assets.zig");
const m = @import("math.zig");
const parallax = @import("parallax.zig");
const portfolio = @import("portfolio.zig");
const render = @import("render.zig");
const w = @import("wasm_bindings.zig");
const ww = @import("wasm.zig");

const defaultTextureWrap = w.GL_CLAMP_TO_EDGE;
const defaultTextureFilter = w.GL_LINEAR;

const refSize = m.Vec2.init(3840, 2000);
const gridRefSize = 74;

const DEPTH_UI_ABOVEALL = 0.0;
const DEPTH_UI_OVER2 = 0.2;
const DEPTH_UI_OVER1 = 0.4;
const DEPTH_UI_GENERIC = 0.5;
const DEPTH_LANDINGIMAGE = 0.6;
const DEPTH_LANDINGBACKGROUND = 0.7;
const DEPTH_GRIDIMAGE = 0.6;
const DEPTH_UI_BELOWALL = 1.0;

const Memory = struct {
    persistent: [128 * 1024]u8 align(8),
    transient: [64 * 1024]u8 align(8),

    const Self = @This();

    fn getState(self: *Self) *State
    {
        return @ptrCast(*State, &self.persistent[0]);
    }

    fn getTransientAllocator(self: *Self) std.heap.FixedBufferAllocator
    {
        return std.heap.FixedBufferAllocator.init(&self.transient);
    }
};

var _memory: *Memory align(8) = undefined;

fn hexU8ToFloatNormalized(hexString: []const u8) !f32
{
    return @intToFloat(f32, try std.fmt.parseUnsigned(u8, hexString, 16)) / 255.0;
}

fn colorHexToVec4(hexString: []const u8) !m.Vec4
{
    if (hexString.len != 7 and hexString.len != 9) {
        return error.BadHexStringLength;
    }
    if (hexString[0] != '#') {
        return error.BadHexString;
    }

    const rHex = hexString[1..3];
    const gHex = hexString[3..5];
    const bHex = hexString[5..7];
    const aHex = if (hexString.len == 9) hexString[7..9] else "ff";
    return m.Vec4.init(
        try hexU8ToFloatNormalized(rHex),
        try hexU8ToFloatNormalized(gHex),
        try hexU8ToFloatNormalized(bHex),
        try hexU8ToFloatNormalized(aHex),
    );
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    w.log(message_level, scope, format, args);
}

const Texture = enum(usize) {
    CategoriesText,
    DecalTopLeft,
    // IconContact,
    // IconHome,
    // IconPortfolio,
    // IconWork,
    LoadingGlyphs,
    Logo343,
    LogoMicrosoft,
    LogosAll,
    StickerCircle,
    StickerShiny,
    SymbolEye,
    WeAreStorytellers,

    StickerMainHome,
};

// return true when pressed
fn updateButton(topLeft: m.Vec2, size: m.Vec2, mouseState: MouseState, scrollY: f32, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    const topLeftScroll = m.Vec2.init(topLeft.x, topLeft.y - scrollY);
    if (m.isInsideRect(mousePosF, topLeftScroll, size)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents[0..mouseState.numClickEvents]) |clickEvent| {
            std.log.info("{}", .{clickEvent});
            const clickPosF = m.Vec2.initFromVec2i(clickEvent.pos);
            if (!clickEvent.down and clickEvent.clickType == ClickType.Left and m.isInsideRect(clickPosF, topLeftScroll, size)) {
                return true;
            }
        }
        return false;
    } else {
        return false;
    }
}

const ParallaxImage = struct {
    url: []const u8,
    factor: f32,
    assetId: ?usize,

    const Self = @This();

    pub fn init(url: []const u8, factor: f32) Self
    {
        return Self{
            .url = url,
            .factor = factor,
            .assetId = null,
        };
    }
};

const ParallaxBgColorType = enum {
    Color,
    Gradient,
};

const ParallaxBgColor = union(ParallaxBgColorType) {
    Color: m.Vec4,
    Gradient: struct {
        colorTop: m.Vec4,
        colorBottom: m.Vec4,
    },
};

const ParallaxSet = struct {
    bgColor: ParallaxBgColor,
    images: []ParallaxImage,
};

fn initParallaxSets(allocator: std.mem.Allocator) ![]ParallaxSet
{
    return try allocator.dupe(ParallaxSet, &[_]ParallaxSet{
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#101010"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax1-1.png", 0.01),
                ParallaxImage.init("/images/parallax/parallax1-2.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax1-3.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax1-4.png", 0.5),
                ParallaxImage.init("/images/parallax/parallax1-5.png", 0.9),
                ParallaxImage.init("/images/parallax/parallax1-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#000000"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax2-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax2-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax2-3.png", 0.25),
                ParallaxImage.init("/images/parallax/parallax2-4.png", 1.0),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#212121"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax3-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax3-2.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax3-3.png", 0.3),
                ParallaxImage.init("/images/parallax/parallax3-4.png", 0.8),
                ParallaxImage.init("/images/parallax/parallax3-5.png", 1.1),
            }),
        },
        .{
            .bgColor = .{
                .Gradient = .{
                    .colorTop = try colorHexToVec4("#1a1b1a"),
                    .colorBottom = try colorHexToVec4("#ffffff"),
                },
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax4-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax4-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax4-3.png", 0.25),
                ParallaxImage.init("/images/parallax/parallax4-4.png", 0.6),
                ParallaxImage.init("/images/parallax/parallax4-5.png", 0.75),
                ParallaxImage.init("/images/parallax/parallax4-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax5-1.png", 0.0),
                ParallaxImage.init("/images/parallax/parallax5-2.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax5-3.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax5-4.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax5-5.png", 0.4),
                ParallaxImage.init("/images/parallax/parallax5-6.png", 0.7),
                ParallaxImage.init("/images/parallax/parallax5-7.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax6-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax6-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax6-3.png", 0.4),
                ParallaxImage.init("/images/parallax/parallax6-4.png", 0.7),
                ParallaxImage.init("/images/parallax/parallax6-5.png", 1.5),
            }),
        },
    });
}

const ClickType = enum {
    Left,
    Middle,
    Right,
    Other,
};

const ClickEvent = struct {
    pos: m.Vec2i,
    clickType: ClickType,
    down: bool,
};

const MouseState = struct {
    pos: m.Vec2i,
    numClickEvents: usize,
    clickEvents: [64]ClickEvent,

    const Self = @This();

    fn init() Self
    {
        return Self {
            .pos = m.Vec2i.zero,
            .numClickEvents = 0,
            .clickEvents = undefined,
        };
    }

    fn clear(self: *Self) void
    {
        self.numClickEvents = 0;
    }

    fn addClickEvent(self: *Self, pos: m.Vec2i, clickType: ClickType, down: bool) void
    {
        const i = self.numClickEvents;
        if (i >= self.clickEvents.len) {
            return;
        }

        self.clickEvents[i] = ClickEvent {
            .pos = pos,
            .clickType = clickType,
            .down = down,
        };
        self.numClickEvents += 1;
    }
};

const KeyEvent = struct {
    keyCode: i32,
    down: bool,
};

const KeyboardState = struct {
    numKeyEvents: usize,
    keyEvents: [64]KeyEvent,

    const Self = @This();

    fn init() Self
    {
        return Self {
            .numKeyEvents = 0,
            .keyEvents = undefined,
        };
    }

    fn clear(self: *Self) void
    {
        self.numKeyEvents = 0;
    }

    fn addKeyEvent(self: *Self, keyCode: i32, down: bool) void
    {
        const i = self.numKeyEvents;
        if (i >= self.keyEvents.len) {
            return;
        }

        self.keyEvents[i] = KeyEvent {
            .keyCode = keyCode,
            .down = down,
        };
        self.numKeyEvents += 1;
    }

    fn keyDown(self: Self, keyCode: i32) bool
    {
        const keyEvents = self.keyEvents[0..self.numKeyEvents];
        var latestDown = false;
        for (keyEvents) |e| {
            if (e.keyCode == keyCode) {
                latestDown = e.down;
            }
        }
        return latestDown;
    }
};

const PageType = enum {
    Home,
    Entry,
};

const PageData = union(PageType) {
    Home: void,
    Entry: struct {
        portfolioIndex: usize,
        galleryImageIndex: ?usize,
    },
};

fn uriToPageData(uri: []const u8) !PageData
{
    if (std.mem.eql(u8, uri, "/")) {
        return PageData {
            .Home = {},
        };
    }
    for (portfolio.PORTFOLIO_LIST) |pf, i| {
        if (std.mem.eql(u8, uri, pf.uri)) {
            return PageData {
                .Entry = .{
                    .portfolioIndex = i,
                    .galleryImageIndex = null,
                }
            };
        }
    }
    return error.UnknownPage;
}

const State = struct {
    fbAllocator: std.heap.FixedBufferAllocator,

    renderState: render.RenderState,
    fbTexture: c_uint,
    fbDepthRenderbuffer: c_uint,
    fb: c_uint,

    assets: assets.Assets(Texture, 256),

    pageData: PageData,
    screenSizePrev: m.Vec2i,
    scrollYPrev: c_int,
    timestampMsPrev: c_int,
    mouseState: MouseState,
    keyboardState: KeyboardState,
    activeParallaxSetIndex: usize,
    parallaxImageSets: []ParallaxSet,
    parallaxTX: f32,
    parallaxIdleTimeMs: c_int,

    debug: bool,

    const Self = @This();
    const PARALLAX_SET_INDEX_START = 3;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    pub fn init(buf: []u8, uri: []const u8) !Self
    {
        var fbAllocator = std.heap.FixedBufferAllocator.init(buf);

        w.glClearColor(0.0, 0.0, 0.0, 1.0);
        w.glEnable(w.GL_DEPTH_TEST);
        w.glDepthFunc(w.GL_LEQUAL);

        w.glEnable(w.GL_BLEND);
        w.glBlendFunc(w.GL_SRC_ALPHA, w.GL_ONE_MINUS_SRC_ALPHA);

        ww.setCursor("auto");

        var self = Self {
            .fbAllocator = fbAllocator,

            .renderState = try render.RenderState.init(),
            .fbTexture = 0,
            .fbDepthRenderbuffer = 0,
            .fb = 0,

            .assets = assets.Assets(Texture, 256).init(fbAllocator.allocator()),

            .pageData = try uriToPageData(uri),
            .screenSizePrev = m.Vec2i.zero,
            .scrollYPrev = -1,
            .timestampMsPrev = 0,
            .mouseState = MouseState.init(),
            .keyboardState = KeyboardState.init(),
            .activeParallaxSetIndex = PARALLAX_SET_INDEX_START,
            .parallaxImageSets = try initParallaxSets(fbAllocator.allocator()),
            .parallaxTX = 0,
            .parallaxIdleTimeMs = 0,

            .debug = false,
        };

        _ = try self.assets.register(.{ .Static = Texture.StickerCircle },
            "/images/sticker-circle.png", defaultTextureWrap, defaultTextureFilter, 2
        );
        _ = try self.assets.register(.{ .Static = Texture.LoadingGlyphs },
            "/images/loading-glyphs.png", defaultTextureWrap, defaultTextureFilter, 2
        );
        _ = try self.assets.register(.{ .Static = Texture.DecalTopLeft },
            "/images/decal-topleft.png", defaultTextureWrap, defaultTextureFilter, 2
        );

        _ = try self.assets.register(.{ .Static = Texture.CategoriesText },
            "/images/categories-text.png", defaultTextureWrap, defaultTextureFilter, 5
        );

        // _ = try self.assets.register(.{ .Static = Texture.IconContact },
        //     "/images/icon-contact.png", defaultTextureWrap, defaultTextureFilter, 5
        // );
        // _ = try self.assets.register(.{ .Static = Texture.IconHome },
        //     "/images/icon-home.png", defaultTextureWrap, defaultTextureFilter, 5
        // );
        // _ = try self.assets.register(.{ .Static = Texture.IconPortfolio },
        //     "/images/icon-portfolio.png", defaultTextureWrap, defaultTextureFilter, 5
        // );
        // _ = try self.assets.register(.{ .Static = Texture.IconWork },
        //     "/images/icon-work.png", defaultTextureWrap, defaultTextureFilter, 5
        // );
        _ = try self.assets.register(.{ .Static = Texture.StickerShiny },
            "/images/sticker-shiny.png", defaultTextureWrap, defaultTextureFilter, 5
        );


        switch (self.pageData) {
            .Home => {
                _ = try self.assets.register(.{ .Static = Texture.LogosAll },
                    "/images/logos-all.png", defaultTextureWrap, defaultTextureFilter, 8
                );
                _ = try self.assets.register(.{ .Static = Texture.StickerMainHome },
                    "/images/sticker-main.png", defaultTextureWrap, defaultTextureFilter, 5
                );
                _ = try self.assets.register(.{ .Static = Texture.SymbolEye },
                    "/images/symbol-eye.png", defaultTextureWrap, defaultTextureFilter, 8
                );
                _ = try self.assets.register(.{ .Static = Texture.WeAreStorytellers },
                    "/images/we-are-storytellers.png", defaultTextureWrap, defaultTextureFilter, 8
                );
            },
            .Entry => {
            },
        }

        return self;
    }

    pub fn deinit(self: Self) void
    {
        self.gpa.deinit();
    }

    pub fn allocator(self: Self) std.mem.Allocator
    {
        return self.fbAllocator.allocator();
    }
};

fn buttonToClickType(button: c_int) ClickType
{
    return switch (button) {
        0 => ClickType.Left,
        1 => ClickType.Middle,
        2 => ClickType.Right,
        else => ClickType.Other,
    };
}

fn tryLoadAndGetParallaxSet(state: *State, index: usize, priority: u32) ?ParallaxSet
{
    if (index >= state.parallaxImageSets.len) {
        return null;
    }

    const parallaxSet = state.parallaxImageSets[index];
    var loaded = true;
    for (parallaxSet.images) |*parallaxImage| {
        if (parallaxImage.assetId) |id| {
            if (state.assets.getTextureData(.{.DynamicId = id})) |parallaxTexData| {
                if (!parallaxTexData.loaded()) {
                    loaded = false;
                    break;
                }
            } else {
                loaded = false;
                std.log.err("Bad asset ID {}", .{id});
            }
        } else {
            loaded = false;
            parallaxImage.assetId = state.assets.register(.{ .DynamicUrl = parallaxImage.url },
                parallaxImage.url, defaultTextureWrap, defaultTextureFilter, priority
            ) catch |err| {
                std.log.err("register texture error {}", .{err});
                break;
            };
        }
    }

    return if (loaded) parallaxSet else null;
}

const GridImage = struct {
    uri: []const u8,
    title: ?[]const u8,
    goToUri: ?[]const u8,
};

fn drawImageGrid(images: []const GridImage, indexOffset: usize, itemsPerRow: usize, topLeft: m.Vec2, width: f32, spacing: f32, fontSize: f32, fontColor: m.Vec4, state: *State, scrollY: f32, mouseHoverGlobal: *bool,renderQueue: *render.RenderQueue, callback: *const fn(*State, GridImage, usize) void) f32
{
    const itemWidth = (width - spacing * (@intToFloat(f32, itemsPerRow) - 1)) / @intToFloat(f32, itemsPerRow);
    const itemSize = m.Vec2.init(itemWidth, itemWidth * 0.5);

    for (images) |img, i| {
        const rowF = @intToFloat(f32, i / itemsPerRow);
        const colF = @intToFloat(f32, i % itemsPerRow);
        const spacingY = if (img.title) |_| spacing * 4 else spacing;
        const itemPos = m.Vec2.init(
            topLeft.x + colF * (itemSize.x + spacing),
            topLeft.y + rowF * (itemSize.y + spacingY)
        );
        if (state.assets.getTextureData(.{.DynamicUrl = img.uri})) |tex| {
            if (tex.loaded()) {
                const cornerRadius = spacing * 2;
                renderQueue.quadTex(
                    itemPos, itemSize, DEPTH_GRIDIMAGE, cornerRadius, tex.id, m.Vec4.one
                );
            }
        } else {
            _ = state.assets.register(.{ .DynamicUrl = img.uri},
                img.uri, defaultTextureWrap, defaultTextureFilter, 9
            ) catch |err| {
                std.log.err("failed to register {s}, err {}", .{img.uri, err});
                return 0;
            };
        }

        if (img.title) |title| {
            const textPos = m.Vec2.init(
                itemPos.x,
                itemPos.y + itemSize.y + spacing * 2
            );
            renderQueue.textLine(
                title, textPos, fontSize, 0.0, fontColor, "HelveticaBold"
            );
        }

        if (updateButton(itemPos, itemSize, state.mouseState, scrollY, mouseHoverGlobal)) {
            callback(state, img, indexOffset + i);
        }
    }

    // TODO doesn't work with titles
    return @intToFloat(f32, ((images.len - 1) / itemsPerRow) + 1) * (itemSize.y + spacing);
}

fn getTextureScaledSize(size: m.Vec2i, screenSize: m.Vec2) m.Vec2
{
    const sizeF = m.Vec2.initFromVec2i(size);
    const scaleFactor = screenSize.y / refSize.y;
    return m.Vec2.multScalar(sizeF, scaleFactor);
}

fn getImageCount(entryData: anytype) usize
{
    const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
    var i: usize = 0;
    for (pf.subprojects) |sub| {
        for (sub.images) |_| {
            i += 1;
        }
    }
    return i;
}

fn getImageUrlFromIndex(entryData: anytype, index: usize) ?[]const u8
{
    const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
    var i: usize = 0;
    for (pf.subprojects) |sub| {
        for (sub.images) |img| {
            if (i == index) {
                return img;
            }
            i += 1;
        }
    }
    return null;
}

export fn onInit() void
{
    std.log.info("onInit", .{});

    _memory = std.heap.page_allocator.create(Memory) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return;
    };
    var memoryBytes = std.mem.asBytes(_memory);
    std.mem.set(u8, memoryBytes, 0);

    var buf: [64]u8 = undefined;
    const uriLen = ww.getUri(&buf);
    const uri = buf[0..uriLen];

    var state = _memory.getState();
    const stateSize = @sizeOf(State);
    var remaining = _memory.persistent[stateSize..];
    std.log.info("memory - {*}\npersistent store - {} ({} state | {} remaining)\ntransient store - {}\ntotal - {}", .{_memory, _memory.persistent.len, stateSize, remaining.len, _memory.transient.len, memoryBytes.len});

    state.* = State.init(remaining, uri) catch |err| {
        std.log.err("State init failed, err {}", .{err});
        return;
    };
}

export fn onMouseMove(x: c_int, y: c_int) void
{
    var state = _memory.getState();
    state.mouseState.pos = m.Vec2i.init(x, y);
}

export fn onMouseDown(button: c_int, x: c_int, y: c_int) void
{
    var state = _memory.getState();
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), true);
}

export fn onMouseUp(button: c_int, x: c_int, y: c_int) void
{
    var state = _memory.getState();
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), false);
}

export fn onKeyDown(keyCode: c_int) void
{
    var state = _memory.getState();
    state.keyboardState.addKeyEvent(keyCode, true);
}

export fn onAnimationFrame(width: c_int, height: c_int, scrollY: c_int, timestampMs: c_int) c_int
{
    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
    const scrollYF = @intToFloat(f32, scrollY);

    var state = _memory.getState();
    defer {
        state.timestampMsPrev = timestampMs;
        state.scrollYPrev = scrollY;
        state.screenSizePrev = screenSizeI;
        state.mouseState.clear();
        state.keyboardState.clear();
    }

    const keyCodeEscape = 27;
    const keyCodeArrowLeft = 37;
    const keyCodeArrowRight = 39;
    const keyCodeG = 71;

    if (state.pageData == .Entry and state.pageData.Entry.galleryImageIndex != null) {
        const imageCount = getImageCount(state.pageData.Entry);
        if (state.keyboardState.keyDown(keyCodeEscape)) {
            state.pageData.Entry.galleryImageIndex = null;
            w.setAllTextOpacity(1.0);
        } else if (state.keyboardState.keyDown(keyCodeArrowLeft)) {
            if (state.pageData.Entry.galleryImageIndex.? == 0) {
                state.pageData.Entry.galleryImageIndex.? = imageCount - 1;
            } else {
                state.pageData.Entry.galleryImageIndex.? -= 1;
            }
        } else if (state.keyboardState.keyDown(keyCodeArrowRight)) {
            state.pageData.Entry.galleryImageIndex.? += 1;
            if (state.pageData.Entry.galleryImageIndex.? >= imageCount) {
                state.pageData.Entry.galleryImageIndex.? = 0;
            }
        }
    }
    if (state.keyboardState.keyDown(keyCodeG)) {
        state.debug = !state.debug;
    }

    const mousePosF = m.Vec2.initFromVec2i(state.mouseState.pos);
    var mouseHoverGlobal = false;

    const deltaMs = if (state.timestampMsPrev > 0) (timestampMs - state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;
    _ = deltaS;

    var tempAllocatorObj = _memory.getTransientAllocator();
    const tempAllocator = tempAllocatorObj.allocator();

    var renderQueue = render.RenderQueue.init(tempAllocator);

    if (!m.Vec2i.eql(state.screenSizePrev, screenSizeI)) {
        std.log.info("resetting screen framebuffer", .{});
        state.fbTexture = w.createTexture(screenSizeI.x, screenSizeI.y, defaultTextureWrap, w.GL_NEAREST);

        state.fb = w.glCreateFramebuffer();
        w.glBindFramebuffer(w.GL_FRAMEBUFFER, state.fb);
        w.glFramebufferTexture2D(w.GL_FRAMEBUFFER, w.GL_COLOR_ATTACHMENT0, w.GL_TEXTURE_2D, state.fbTexture, 0);

        state.fbDepthRenderbuffer = w.glCreateRenderbuffer();
        w.glBindRenderbuffer(w.GL_RENDERBUFFER, state.fbDepthRenderbuffer);
        w.glRenderbufferStorage(w.GL_RENDERBUFFER, w.GL_DEPTH_COMPONENT16, screenSizeI.x, screenSizeI.y);
        w.glFramebufferRenderbuffer(w.GL_FRAMEBUFFER, w.GL_DEPTH_ATTACHMENT, w.GL_RENDERBUFFER, state.fbDepthRenderbuffer);
    }

    if (state.scrollYPrev != scrollY) {
    }
    // TODO
    // } else {
    //     return 0;
    // }

    const fontStickerSize = 124 / refSize.y * screenSizeF.y;
    // const fontStickerSmallSize = 26 / refSize.y * screenSizeF.y;
    const fontSubtitleSize = 84 / refSize.y * screenSizeF.y;
    const fontTextSize = 30 / refSize.y * screenSizeF.y;
    const gridSize = std.math.round(gridRefSize / refSize.y * screenSizeF.y);

    const marginX = blk: {
        const maxLandingImageAspect = 2.15;
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - gridSize * 2.0,
            screenSizeF.y - gridSize * 3.0
        );
        const adjustedWidth = std.math.min(landingImageSize.x, landingImageSize.y * maxLandingImageAspect);
        break :blk (landingImageSize.x - adjustedWidth) / 2.0;
    };

    w.glBindFramebuffer(w.GL_FRAMEBUFFER, state.fb);

    w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

    const aspect = screenSizeF.x / screenSizeF.y;
    const isVertical = aspect <= 1.0;
    _ = isVertical; // TODO

    // const colorWhite = m.Vec4.init(1.0, 1.0, 1.0, 1.0);
    const colorBlack = m.Vec4.init(0.0, 0.0, 0.0, 1.0);
    const colorYellowHome = m.Vec4.init(234.0 / 255.0, 1.0, 0.0, 1.0);
    const colorUi = blk: {
        switch (state.pageData) {
            .Home => {
                break :blk colorYellowHome;
            },
            .Entry => |entryData| {
                const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
                break :blk pf.colorUi;
            },
        }
    };
    const colorRedSticker = m.Vec4.init(234.0 / 255.0, 65.0 / 255.0, 0.0, 1.0);
    const parallaxMotionMax = screenSizeF.x / 8.0;

    // ==== LANDING IMAGE ====

    // get landing UI elements to see if they are loaded
    // const iconTextures = [_]Texture {
    //     Texture.IconHome,
    //     Texture.IconPortfolio,
    //     Texture.IconWork,
    //     Texture.IconContact,
    // };
    var allIconsLoaded = true;
    const categoriesText = state.assets.getStaticTextureData(Texture.CategoriesText);
    // for (iconTextures) |iconTexture| {
    //     if (!state.assets.getStaticTextureData(iconTexture).loaded()) {
    //         allIconsLoaded = false;
    //         break;
    //     }
    // }

    const decalTopLeft = state.assets.getStaticTextureData(Texture.DecalTopLeft);
    const stickerMain = blk: {
        switch (state.pageData) {
            .Home => break :blk state.assets.getStaticTextureData(Texture.StickerMainHome),
            .Entry => |entryData| {
                const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
                if (state.assets.getTextureData(.{.DynamicUrl = pf.sticker})) |tex| {
                    break :blk tex;
                } else {
                    _ = state.assets.register(.{ .DynamicUrl = pf.sticker},
                        pf.sticker, defaultTextureWrap, defaultTextureFilter, 5
                    ) catch |err| {
                        std.log.err("failed to register {s}, err {}", .{pf.sticker, err});
                        return 0;
                    };

                    if (state.assets.getTextureData(.{.DynamicUrl = pf.sticker})) |tex| {
                        break :blk tex;
                    } else {
                        std.log.err("no texture data after register for {s}", .{pf.sticker});
                        return 0;
                    }
                }
            },
        }
    };
    const stickerShiny = state.assets.getStaticTextureData(Texture.StickerShiny);

    var allLandingAssetsLoaded = allIconsLoaded and categoriesText.loaded() and decalTopLeft.loaded() and stickerMain.loaded() and stickerShiny.loaded();

    const landingImagePos = m.Vec2.init(
        marginX + gridSize * 1,
        gridSize * 1
    );
    const landingImageSize = m.Vec2.init(
        screenSizeF.x - marginX * 2 - gridSize * 2,
        screenSizeF.y - gridSize * 3
    );
    switch (state.pageData) {
        .Home => {
            // Determine whether the active parallax set is loaded
            var activeParallaxSet = tryLoadAndGetParallaxSet(state, state.activeParallaxSetIndex, 5);
            const parallaxSetSwapSeconds = 6;
            if (activeParallaxSet) |_| {
                state.parallaxIdleTimeMs += deltaMs;
                const nextSetIndex = (state.activeParallaxSetIndex + 1) % state.parallaxImageSets.len;
                var nextParallaxSet = tryLoadAndGetParallaxSet(state, nextSetIndex, 20);
                if (nextParallaxSet) |_| {
                    if (state.parallaxIdleTimeMs >= parallaxSetSwapSeconds * 1000) {
                        state.parallaxIdleTimeMs = 0;
                        state.activeParallaxSetIndex = nextSetIndex;
                        activeParallaxSet = nextParallaxSet;
                    } else {
                        for (state.parallaxImageSets) |_, i| {
                            if (tryLoadAndGetParallaxSet(state, i, 20) == null) {
                                break;
                            }
                        }
                    }
                }
            }

            const targetParallaxTX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
            state.parallaxTX = targetParallaxTX;

            if (allLandingAssetsLoaded) {
                if (activeParallaxSet) |parallaxSet| {
                    switch (parallaxSet.bgColor) {
                        .Color => |color| {
                            renderQueue.quad(landingImagePos, landingImageSize, DEPTH_LANDINGBACKGROUND, 0, color);
                        },
                        .Gradient => |gradient| {
                            renderQueue.quadGradient(
                                landingImagePos, landingImageSize, DEPTH_LANDINGBACKGROUND, 0,
                                gradient.colorTop, gradient.colorTop,
                                gradient.colorBottom, gradient.colorBottom);
                        },
                    }

                    for (parallaxSet.images) |parallaxImage| {
                        const assetId = parallaxImage.assetId orelse continue;
                        const textureData = state.assets.getTextureData(.{.DynamicId = assetId}) orelse continue;
                        if (!textureData.loaded()) continue;

                        const textureSize = getTextureScaledSize(textureData.size, screenSizeF);
                        const parallaxOffsetX = state.parallaxTX * parallaxMotionMax * parallaxImage.factor;

                        const imgPos = m.Vec2.init(
                            screenSizeF.x / 2.0 - textureSize.x / 2.0 + parallaxOffsetX,
                            landingImagePos.y
                        );
                        const imgSize = m.Vec2.init(textureSize.x, landingImageSize.y);
                        renderQueue.quadTex(imgPos, imgSize, DEPTH_LANDINGIMAGE, 0.0, textureData.id, m.Vec4.one);
                    }
                } else {
                    allLandingAssetsLoaded = false;
                }
            }
        },
        .Entry => |entryData| {
            const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
            if (state.assets.getTextureData(.{.DynamicUrl = pf.landing})) |landingTex| {
                if (allLandingAssetsLoaded and landingTex.loaded()) {
                    const textureSize = getTextureScaledSize(landingTex.size, screenSizeF);
                    const imgPos = m.Vec2.init(
                        screenSizeF.x / 2.0 - textureSize.x / 2.0,
                        landingImagePos.y
                    );
                    const imgSize = m.Vec2.init(textureSize.x, landingImageSize.y);
                    renderQueue.quadTex(imgPos, imgSize, DEPTH_LANDINGIMAGE, 0.0, landingTex.id, m.Vec4.one);
                } else {
                    allLandingAssetsLoaded = false;
                }
            } else {
                allLandingAssetsLoaded = false;
                _ = state.assets.register(.{.DynamicUrl = pf.landing},
                    pf.landing, defaultTextureWrap, defaultTextureFilter, 5
                ) catch |err| {
                    std.log.err("register failed for {s} error {}", .{pf.landing, err});
                };
            }
        },
    }

    if (decalTopLeft.loaded()) {
        // landing page, four corners
        const decalSize = m.Vec2.init(gridSize * 5, gridSize * 5);
        const decalMargin = gridSize * 2;

        const posTL = m.Vec2.init(
            marginX + decalMargin,
            decalMargin,
        );
        const uvOriginTL = m.Vec2.init(0, 0);
        const uvSizeTL = m.Vec2.init(1, 1);
        renderQueue.quadTexUvOffset(
            posTL, decalSize, DEPTH_UI_GENERIC, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi
        );

        const posTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            decalMargin,
        );
        const uvOriginTR = m.Vec2.init(1, 0);
        const uvSizeTR = m.Vec2.init(-1, 1);
        renderQueue.quadTexUvOffset(
            posTR, decalSize, DEPTH_UI_GENERIC, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi
        );

        const posBL = m.Vec2.init(
            marginX + decalMargin,
            screenSizeF.y - decalMargin - gridSize - decalSize.y,
        );
        const uvOriginBL = m.Vec2.init(0, 1);
        const uvSizeBL = m.Vec2.init(1, -1);
        renderQueue.quadTexUvOffset(
            posBL, decalSize, DEPTH_UI_GENERIC, 0, uvOriginBL, uvSizeBL, decalTopLeft.id, colorUi
        );

        const posBR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            screenSizeF.y - decalMargin - gridSize - decalSize.y,
        );
        const uvOriginBR = m.Vec2.init(1, 1);
        const uvSizeBR = m.Vec2.init(-1, -1);
        renderQueue.quadTexUvOffset(
            posBR, decalSize, DEPTH_UI_GENERIC, 0, uvOriginBR, uvSizeBR, decalTopLeft.id, colorUi
        );

        // content page, 2 start
        const posContentTL = m.Vec2.init(
            marginX + decalMargin,
            screenSizeF.y + gridSize * 2,
        );
        renderQueue.quadTexUvOffset(
            posContentTL, decalSize, DEPTH_UI_GENERIC, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi
        );
        const posContentTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            screenSizeF.y + gridSize * 2,
        );
        renderQueue.quadTexUvOffset(
            posContentTR, decalSize, DEPTH_UI_GENERIC, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi
        );
    }

    const stickerCircle = state.assets.getStaticTextureData(Texture.StickerCircle);
    const loadingGlyphs = state.assets.getStaticTextureData(Texture.LoadingGlyphs);

    if (allLandingAssetsLoaded) {
        if (categoriesText.loaded()) {
            const categoriesSize = getTextureScaledSize(categoriesText.size, screenSizeF);
            const categoriesPos = m.Vec2.init(
                marginX + gridSize * 5,
                gridSize * 5,
            );
            renderQueue.quadTex(categoriesPos, categoriesSize, DEPTH_UI_GENERIC, 0, categoriesText.id, colorUi);

            const homeSize = m.Vec2.init(categoriesSize.x / 6.0, categoriesSize.y);
            if (updateButton(categoriesPos, homeSize, state.mouseState, scrollYF, &mouseHoverGlobal)) {
                ww.setUri("/");
            }
        }
        // for (iconTextures) |iconTexture, i| {
        //     const textureData = state.assets.getStaticTextureData(iconTexture);

        //     const iF = @intToFloat(f32, i);
        //     const iconSizeF = m.Vec2.init(
        //         gridSize * 2.162,
        //         gridSize * 2.162,
        //     );
        //     const iconPos = m.Vec2.init(
        //         marginX + gridSize * 5 + gridSize * 2.5 * iF,
        //         gridSize * 5,
        //     );
        //     renderQueue.quadTex(
        //         iconPos, iconSizeF, DEPTH_UI_GENERIC, 0, textureData.id, colorUi
        //     );
        //     if (updateButton(iconPos, iconSizeF, state.mouseState, scrollYF, &mouseHoverGlobal)) {
        //         const uri = switch (iconTexture) {
        //             .IconHome => "/",
        //             else => continue,
        //         };
        //         ww.setUri(uri);
        //     }
        // }

        // sticker (main)
        const stickerSize = getTextureScaledSize(stickerMain.size, screenSizeF);
        const stickerPos = m.Vec2.init(
            marginX + gridSize * 5.0,
            screenSizeF.y - gridSize * 6 - stickerSize.y
        );
        const colorSticker = blk: {
            switch (state.pageData) {
                .Home => break :blk colorUi,
                .Entry => |entryData| {
                    const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
                    break :blk pf.colorSticker;
                },
            }
        };
        renderQueue.quadTex(
            stickerPos, stickerSize, DEPTH_UI_GENERIC, 0, stickerMain.id, colorSticker
        );

        // sticker (shiny)
        const stickerShinySize = getTextureScaledSize(stickerShiny.size, screenSizeF);
        const stickerShinyPos = m.Vec2.init(
            screenSizeF.x - marginX - gridSize * 5.0 - stickerShinySize.x,
            gridSize * 5.0
        );
        renderQueue.quadTex(stickerShinyPos, stickerShinySize, DEPTH_UI_GENERIC, 0, stickerShiny.id, m.Vec4.one);
    } else {
        // show loading indicator, if that is loaded
        if (stickerCircle.loaded() and loadingGlyphs.loaded()) {
            const circleSize = getTextureScaledSize(stickerCircle.size, screenSizeF);
            const circlePos = m.Vec2.init(
                screenSizeF.x / 2.0 - circleSize.x / 2.0,
                screenSizeF.y / 2.0 - circleSize.y / 2.0 - gridSize * 1,
            );
            renderQueue.quadTex(circlePos, circleSize, DEPTH_UI_GENERIC, 0, stickerCircle.id, colorUi);

            const glyphsSize = getTextureScaledSize(loadingGlyphs.size, screenSizeF);
            const glyphsPos = m.Vec2.init(
                screenSizeF.x / 2.0 - glyphsSize.x / 2.0,
                screenSizeF.y / 2.0 - glyphsSize.y / 2.0 + gridSize * 1,
            );
            renderQueue.quadTex(glyphsPos, glyphsSize, DEPTH_UI_GENERIC, 0, loadingGlyphs.id, colorUi);

            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                const spacing = gridSize * 0.28;
                const dotSize = m.Vec2.init(gridSize * 0.16, gridSize * 0.16);
                const dotOrigin = m.Vec2.init(
                    screenSizeF.x / 2.0 - dotSize.x / 2.0 - spacing * @intToFloat(f32, i - 1),
                    screenSizeF.y / 2.0 - dotSize.y / 2.0 - gridSize * 1,
                );
                renderQueue.quad(dotOrigin, dotSize, DEPTH_UI_GENERIC - 0.01, 0, colorBlack);
            }
        }
    }

    // rounded black frame
    const framePos = m.Vec2.init(marginX + gridSize * 1, gridSize * 1);
    const frameSize = m.Vec2.init(
        screenSizeF.x - marginX * 2 - gridSize * 2,
        screenSizeF.y - gridSize * 3,
    );
    renderQueue.roundedFrame(m.Vec2.zero, screenSizeF, DEPTH_UI_OVER1, framePos, frameSize, gridSize, colorBlack);

    // ==== BELOW LANDING IMAGE ====

    const separatorLinePos = m.Vec2.init(gridSize + marginX, screenSizeF.y);
    const separatorLineSize = m.Vec2.init(screenSizeF.x - marginX * 2 - gridSize * 2, 1);
    renderQueue.quad(separatorLinePos, separatorLineSize, DEPTH_UI_GENERIC, 0, colorUi);

    const lineHeight = fontTextSize * 1.5;
    var sectionSize: f32 = 0;
    switch (state.pageData) {
        .Home => {
            const weAreStorytellers = state.assets.getStaticTextureData(Texture.WeAreStorytellers);
            const logosAll = state.assets.getStaticTextureData(Texture.LogosAll);
            const symbolEye = state.assets.getStaticTextureData(Texture.SymbolEye);

            if (weAreStorytellers.loaded() and logosAll.loaded() and symbolEye.loaded()) {
                const wasSize = getTextureScaledSize(weAreStorytellers.size, screenSizeF);
                const wasPos = m.Vec2.init(
                    (screenSizeF.x - wasSize.x) / 2,
                    screenSizeF.y + gridSize * 5
                );
                renderQueue.quadTex(wasPos, wasSize, DEPTH_UI_GENERIC, 0, weAreStorytellers.id, colorUi);

                const eyeSize = getTextureScaledSize(stickerCircle.size, screenSizeF);
                const eyePos = m.Vec2.init(
                    screenSizeF.x / 2 - gridSize * 8.6,
                    screenSizeF.y + gridSize * 6.2
                );
                const eyeStickerColor = m.Vec4.init(116.0 / 255.0, 19.0 / 255.0, 179.0 / 255.0, 1.0);
                renderQueue.quadTex(eyePos, eyeSize, DEPTH_UI_GENERIC - 0.01, 0, stickerCircle.id, eyeStickerColor);
                renderQueue.quadTex(eyePos, eyeSize, DEPTH_UI_GENERIC - 0.02, 0, symbolEye.id, colorUi);

                const logosSize = getTextureScaledSize(logosAll.size, screenSizeF);
                const logosPos = m.Vec2.init(
                    (screenSizeF.x - logosSize.x) / 2,
                    screenSizeF.y + gridSize * 18
                );
                renderQueue.quadTex(logosPos, logosSize, DEPTH_UI_GENERIC, 0, logosAll.id, colorUi);
            }

            const textSubPos = m.Vec2.init(marginX + gridSize * 5.5, screenSizeF.y + gridSize * 14.5);
            renderQueue.textBox(
                "Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries. Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision, along with the visuals needed to create a shared understanding between multiple deparments or disciplines.",
                textSubPos, screenSizeF.x - marginX * 2 - gridSize * 5.5 * 2,
                fontTextSize, lineHeight, 0.0,
                colorUi, "HelveticaMedium", .Left
            );

            sectionSize = gridSize * 18 + gridSize * 7;
        },
        .Entry => {
            sectionSize = gridSize * 4;
        },
    }

    // const textSubLeftPos = m.Vec2.init(
    //     marginX + gridSize * 5.5,
    //     screenSizeF.y
    // );
    // renderQueue.textBox(
    //     "Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries.",
    //     textSubLeftPos, gridSize * 13,
    //     fontTextSize, lineHeight, 0.0,
    //     colorUi, "HelveticaMedium", .Left
    // );
    // const textSubRightPos = m.Vec2.init(
    //     marginX + gridSize * 19.5,
    //     screenSizeF.y
    // );
    // renderQueue.textBox(
    //     "Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision, along with the visuals needed to create a shared understanding between multiple deparments or disciplines.",
    //     textSubRightPos, gridSize * 13,
    //     fontTextSize, lineHeight, 0.0,
    //     colorUi, "HelveticaMedium", .Left
    // );

    // if (state.pageData == .Entry) {
    //     const logoMicrosoft = state.assets.getStaticTextureData(Texture.LogoMicrosoft);
    //     const logo343 = state.assets.getStaticTextureData(Texture.Logo343);
    //     if (logoMicrosoft.loaded() and logo343.loaded()) {
    //         const yBase = textSubRightPos.y + gridSize * 2.0;
    //         const size343 = getTextureScaledSize(logo343.size, screenSizeF);
    //         const pos343 = m.Vec2.init(
    //             screenSizeF.x - marginX - gridSize * 5.5 - size343.x + gridSize * 0.5,
    //             yBase - size343.y
    //         );
    //         renderQueue.quadTex(pos343, size343, 0.0, logo343.id, colorUi);

    //         const sizeMicrosoft = getTextureScaledSize(logoMicrosoft.size, screenSizeF);
    //         const posMicrosoft = m.Vec2.init(
    //             pos343.x - gridSize * 3 - sizeMicrosoft.x,
    //             yBase - sizeMicrosoft.y
    //         );
    //         renderQueue.quadTex(posMicrosoft, sizeMicrosoft, 0.0, logoMicrosoft.id, colorUi);

    //     }
    // }

    // content section
    const baseY = screenSizeF.y + sectionSize;
    const headerText = switch (state.pageData) {
        .Home => "projects",
        .Entry => "boarding the mechanics ***",
    };
    const subText = switch (state.pageData) {
        .Home => "In alchemy, the term chrysopoeia (from Greek χρυσοποιία, khrusopoiia, \"gold-making\") refers to the artificial production of gold, most commonly by the alleged transmutation of base metals such as lead. A related term is argyropoeia (ἀργυροποιία, arguropoiia, \"silver-making\"), referring to the artificial production...",
        .Entry => "In 2010, Yorstory partnered with Microsoft/343 Studios to join one of the video game industry's most iconic franchises - Halo. Working with the team's weapons and mission designers, we were tasked with helping visualize some of the game's weapons and idealized gameplay scenarios. The result was an exciting blend of enthusiasm sci-fi mayhem, starring the infamous Master Chief.",
    };

    const contentHeaderPos = m.Vec2.init(
        marginX + gridSize * 5.5,
        baseY + gridSize * 3.0,
    );
    renderQueue.textLine(
        headerText,
        contentHeaderPos, fontStickerSize, 0.0,
        colorUi, "HelveticaBold"
    );

    const contentSubPos = m.Vec2.init(
        marginX + gridSize * 5.5,
        baseY + gridSize * 4.5,
    );
    const contentSubWidth = screenSizeF.x - marginX * 2 - gridSize * 5.5 * 2;
    renderQueue.textBox(
        subText,
        contentSubPos, contentSubWidth,
        fontTextSize, lineHeight, 0.0,
        colorUi, "HelveticaMedium", .Left
    );

    const CB = struct {
        fn home(theState: *State, image: GridImage, index: usize) void
        {
            _ = theState; _ = index;

            if (image.goToUri) |uri| {
                ww.setUri(uri);
            }
        }

        fn entry(theState: *State, image: GridImage, index: usize) void
        {
            _ = image;

            if (theState.pageData != .Entry) {
                std.log.err("entry callback, but not an Entry page", .{});
                return;
            }
            if (theState.pageData.Entry.galleryImageIndex == null) {
                theState.pageData.Entry.galleryImageIndex = index;
                w.setAllTextOpacity(0.0);
            }
        }
    };


    var yMax: f32 = baseY + gridSize * 6.5;
    if (state.pageData == .Entry) {
        const entryData = state.pageData.Entry;

        const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
        var images = std.ArrayList(GridImage).init(tempAllocator);

        const x = marginX + gridSize * 5.5;
        var y = baseY + gridSize * 9;
        var indexOffset: usize = 0; // TODO eh...
        for (pf.subprojects) |sub, i| {
            const numberSizeIsh = gridSize * 2.16;
            const numberSize = getTextureScaledSize(stickerCircle.size, screenSizeF);
            const numberPos = m.Vec2.init(
                marginX + gridSize * 2.5,
                y - gridSize * 2.25,
            );
            if (stickerCircle.loaded()) {
                renderQueue.quadTex(
                    numberPos, numberSize, DEPTH_UI_GENERIC, 0, stickerCircle.id, colorRedSticker
                );
            }
            const numStr = std.fmt.allocPrint(tempAllocator, "{}", .{i + 1}) catch unreachable;
            const numberTextPos = m.Vec2.init(
                numberPos.x + gridSize * 0.1,
                numberPos.y + gridSize * 0.1
            );
            const numberLineHeight = numberSizeIsh;
            renderQueue.textBox(
                numStr, numberTextPos, numberSizeIsh, fontStickerSize, numberLineHeight, 0.0,
                colorBlack, "HelveticaBold", .Center
            );

            renderQueue.textLine(
                sub.name, m.Vec2.init(x, y), fontSubtitleSize, 0.0, colorUi, "HelveticaLight"
            );
            y += gridSize * 1;

            renderQueue.textBox(
                sub.description, m.Vec2.init(x, y), contentSubWidth, fontTextSize, lineHeight, 0.0, colorUi, "HelveticaMedium", .Left
            );
            y += gridSize * 2;

            images.clearRetainingCapacity();
            for (sub.images) |img| {
                images.append(GridImage {
                    .uri = img,
                    .title = null,
                    .goToUri = null,
                }) catch |err| {
                    std.log.err("image append failed {}", .{err});
                };
            }

            const itemsPerRow = 6;
            const topLeft = m.Vec2.init(x, y);
            const spacing = gridSize * 0.25;
            y += drawImageGrid(images.items, indexOffset, itemsPerRow, topLeft, contentSubWidth, spacing, fontTextSize, colorUi, state, scrollYF, &mouseHoverGlobal, &renderQueue, CB.entry);
            y += gridSize * 3;
            indexOffset += sub.images.len;
        }

        yMax = y + gridSize * 1;
    }

    // video embed
    switch (state.pageData) {
        .Home => {},
        .Entry => |entryData| {
            const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];

            if (pf.youtubeId) |youtubeId| {
                const embedWidth = screenSizeF.x - marginX * 2 - gridSize * 5.5 * 2;
                const embedSize = m.Vec2.init(embedWidth, embedWidth / 2.0);
                const embedPos = m.Vec2.init(marginX + gridSize * 5.5, yMax);
                renderQueue.embedYoutube(embedPos, embedSize, youtubeId);
                yMax += embedSize.y + gridSize * 4;
            }
        },
    }

    // projects
    if (state.pageData == .Entry) {
        const opos = m.Vec2.init(
            marginX + gridSize * 5.5,
            yMax,
        );
        renderQueue.textLine(
            "other projects",
            opos, fontStickerSize, 0.0,
            colorUi, "HelveticaBold"
        );

        yMax += gridSize * 2;
    }

    var images = std.ArrayList(GridImage).init(tempAllocator);
    for (portfolio.PORTFOLIO_LIST) |pf, i| {
        if (state.pageData == .Entry and state.pageData.Entry.portfolioIndex == i) {
            continue;
        }

        images.append(GridImage {
            .uri = pf.cover,
            .title = pf.title,
            .goToUri = pf.uri,
        }) catch |err| {
            std.log.err("image append failed {}", .{err});
        };
    }

    const itemsPerRow = 3;
    const topLeft = m.Vec2.init(
        marginX + gridSize * 5.5,
        yMax,
    );
    const spacing = gridSize * 0.25;
    const y = drawImageGrid(images.items, 0, itemsPerRow, topLeft, contentSubWidth, spacing, fontTextSize, colorUi, state, scrollYF, &mouseHoverGlobal, &renderQueue, CB.home);

    yMax += y + gridSize * 3;

    if (state.pageData == .Entry) {
        const entryData = state.pageData.Entry;
        if (entryData.galleryImageIndex) |ind| {
            const pos = m.Vec2.init(0.0, scrollYF);
            renderQueue.quad(pos, screenSizeF, DEPTH_UI_OVER2, 0, m.Vec4.init(0.0, 0.0, 0.0, 1.0));

            if (getImageUrlFromIndex(entryData, ind)) |imageUrl| {
                std.log.info("{s}", .{imageUrl});
                if (state.assets.getTextureData(.{.DynamicUrl = imageUrl})) |imageTex| {
                    if (imageTex.loaded()) {
                        const imageRefSizeF = m.Vec2.initFromVec2i(imageTex.size);
                        const targetHeight = screenSizeF.y - gridSize * 4.0;
                        const imageSize = m.Vec2.init(
                            targetHeight / imageRefSizeF.y * imageRefSizeF.x,
                            targetHeight
                        );
                        const imagePos = m.Vec2.init(
                            (screenSizeF.x - imageSize.x) / 2.0,
                            scrollYF + gridSize * 2.0
                        );
                        // const imagePos = m.Vec2.add(pos, m.Vec2.init(gridSize, gridSize));
                        renderQueue.quadTex(imagePos, imageSize, DEPTH_UI_OVER2 - 0.01, 0, imageTex.id, m.Vec4.one);

                        const clickEvents = state.mouseState.clickEvents[0..state.mouseState.numClickEvents];
                        for (clickEvents) |e| {
                            if (e.clickType == .Left and e.down) {
                                const posF = m.Vec2.initFromVec2i(e.pos);
                                if (posF.x < (screenSizeF.x - imageSize.x) / 2.0
                                    or posF.x > (screenSizeF.x + imageSize.x) / 2.0
                                    or posF.y < (gridSize * 2.0)
                                    or posF.y > (screenSizeF.y - gridSize * 2.0)) {
                                    state.pageData.Entry.galleryImageIndex = null;
                                    w.setAllTextOpacity(1.0);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (state.debug) {
        renderQueue.quad(m.Vec2.init(0, baseY), m.Vec2.init(screenSizeF.x, 1), DEPTH_UI_ABOVEALL, 0, m.Vec4.one);
    }

    renderQueue.renderShapes(state.renderState, screenSizeF, scrollYF);
    if (!m.Vec2i.eql(state.screenSizePrev, screenSizeI)) {
        std.log.info("resize, clearing text", .{});
        w.clearAllText();
        renderQueue.renderText();
        w.clearAllEmbeds();
        renderQueue.renderEmbeds();
    }

    // TODO don't do all the time
    if (mouseHoverGlobal) {
        ww.setCursor("pointer");
    } else {
        ww.setCursor("auto");
    }

    w.bindNullFramebuffer();
    w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);
    state.renderState.postProcessState.draw(state.fbTexture, screenSizeF);

    const maxInflight = 4;
    state.assets.loadQueued(maxInflight);

    // debug grid
    if (state.debug) {
        const halfGridSize = gridSize / 2.0;
        const colorGrid = m.Vec4.init(0.6, 0.6, 0.6, 1.0);
        const colorGridHalf = m.Vec4.init(0.2, 0.2, 0.2, 1.0);

        var i: i32 = undefined;

        const nH = 20;
        const sizeH = m.Vec2.init(screenSizeF.x, 1);
        i = 0;
        while (i < nH) : (i += 1) {
            const iF = @intToFloat(f32, i);
            const color = if (@rem(i, 2) == 0) colorGrid else colorGridHalf;
            const posTop = m.Vec2.init(0, screenSizeF.y - halfGridSize * iF);
            state.renderState.quadState.drawQuad(posTop, sizeH, DEPTH_UI_ABOVEALL, 0, color, screenSizeF);
            const posBottom = m.Vec2.init(0, halfGridSize * iF);
            state.renderState.quadState.drawQuad(posBottom, sizeH, DEPTH_UI_ABOVEALL, 0, color, screenSizeF);
        }

        const nV = 40;
        const sizeV = m.Vec2.init(1, screenSizeF.y);
        i = 0;
        while (i < nV) : (i += 1) {
            const iF = @intToFloat(f32, i);
            const color = if (@rem(i, 2) == 0) colorGrid else colorGridHalf;
            const posLeft = m.Vec2.init(marginX + halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posLeft, sizeV, DEPTH_UI_ABOVEALL, 0, color, screenSizeF);
            const posRight = m.Vec2.init(-marginX + screenSizeF.x - halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posRight, sizeV, DEPTH_UI_ABOVEALL, 0, color, screenSizeF);
        }
    }

    return @floatToInt(c_int, yMax);
}

export fn onTextureLoaded(textureId: c_uint, width: c_int, height: c_int) void
{
    std.log.info("onTextureLoaded {}: {} x {}", .{textureId, width, height});

    var state = _memory.getState();
    state.assets.onTextureLoaded(textureId, m.Vec2i.init(width, height)) catch |err| {
        std.log.err("onTextureLoaded error {}", .{err});
    };
}
