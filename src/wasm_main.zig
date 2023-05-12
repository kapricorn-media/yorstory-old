const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-common-app");
const m = @import("zigkm-common-math");
const w = app.wasm_bindings;

pub usingnamespace app.exports;
pub usingnamespace @import("zigkm-common-stb").exports; // for stb linking

const asset = @import("asset.zig");
// const input = @import("wasm_input.zig");
// const m = @import("math.zig");
const parallax = @import("parallax.zig");
const portfolio = @import("portfolio.zig");
// const render = @import("render.zig");
// const w = @import("wasm_bindings.zig");
// const wasm_app = @import("wasm_app.zig");
// const wasm_asset = @import("wasm_asset.zig");
// const wasm_core = @import("wasm_core.zig");
// const ww = @import("wasm.zig");

// Set up wasm export functions and logging.
// pub const log = wasm_core.log;
// pub usingnamespace wasm_app;
// usingnamespace wasm_core;

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const SIZE_PERMANENT = 256 * 1024;
const SIZE_TRANSIENT = 32 * 1024 * 1024;

pub const MEMORY_FOOTPRINT = SIZE_PERMANENT + SIZE_TRANSIENT;

// const defaultTextureWrap = w.GL_CLAMP_TO_EDGE;
// const defaultTextureFilter = w.GL_LINEAR;
const defaultTextureFilter = app.asset_data.TextureFilter.linear;
const defaultTextureWrap = app.asset_data.TextureWrapMode.clampToEdge;

const refSizeDesktop = m.Vec2.init(3840, 2000);
const refSizeMobile = m.Vec2.init(1080, 1920);

const DEPTH_UI_ABOVEALL = 0.0;
const DEPTH_UI_OVER2 = 0.2;
const DEPTH_UI_OVER1 = 0.4;
const DEPTH_UI_GENERIC = 0.5;
const DEPTH_LANDINGIMAGE = 0.6;
const DEPTH_LANDINGBACKGROUND = 0.7;
const DEPTH_GRIDIMAGE = 0.6;
const DEPTH_UI_BELOWALL = 1.0;

const COLOR_YELLOW_HOME = m.Vec4.init(234.0 / 255.0, 1.0, 0.0, 1.0);

fn isVerticalAspect(screenSize: m.Vec2) bool
{
    const aspect = screenSize.x / screenSize.y;
    return aspect <= 1.0;
}

fn getGridSize(screenSize: m.Vec2) f32
{
    const gridRefSize = 80;
    if (isVerticalAspect(screenSize)) {
        return std.math.round(gridRefSize / refSizeMobile.x * screenSize.x);
    } else {
        return std.math.round(gridRefSize / refSizeDesktop.y * screenSize.y);
    }
}

fn fromRefFontSizePx(refFontSizePx: f32, screenSize: m.Vec2) f32
{
    if (isVerticalAspect(screenSize)) {
        const magicFactor = 1.0;
        return refFontSizePx / refSizeMobile.x * screenSize.x * magicFactor;
    } else {
        const magicFactor = 1.0;
        return refFontSizePx / refSizeDesktop.y * screenSize.y * magicFactor;
    }
}

// return true when pressed
fn updateButton(topLeft: m.Vec2, size: m.Vec2, mouseState: app.input.MouseState, scrollY: f32, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    const topLeftScroll = m.Vec2.init(topLeft.x, topLeft.y - scrollY);
    if (m.isInsideRect(mousePosF, topLeftScroll, size)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents[0..mouseState.numClickEvents]) |clickEvent| {
            const clickPosF = m.Vec2.initFromVec2i(clickEvent.pos);
            if (!clickEvent.down and clickEvent.clickType == app.input.ClickType.Left and m.isInsideRect(clickPosF, topLeftScroll, size)) {
                return true;
            }
        }
        return false;
    } else {
        return false;
    }
}

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

pub const App = struct {
    memory: app.memory.Memory,
    inputState: app.input.InputState,
    renderState: app.render.RenderState,
    assets: app.asset.AssetsWithIds(asset.Font, asset.Texture, 256),
    // fbAllocator: std.heap.FixedBufferAllocator,

    // renderState: render.RenderState,
    fbTexture: c_uint,
    fbDepthRenderbuffer: c_uint,
    fb: c_uint,

    // assets: wasm_asset.Assets(asset.Texture, 256, asset.Font),

    pageData: PageData,
    screenSizePrev: m.Vec2usize,
    scrollYPrev: i32,
    timestampMsPrev: u64,
    // mouseState: input.MouseState,
    // keyboardState: input.KeyboardState,
    // deviceState: input.DeviceState,
    activeParallaxSetIndex: usize,
    parallaxTX: f32,
    parallaxIdleTimeMs: u64,
    yMaxPrev: i32,

    // mobile
    anglesRef: m.Vec3,

    debug: bool,

    const Self = @This();
    const PARALLAX_SET_INDEX_START = 6;
    const PARALLAX_SET_SWAP_SECONDS = 6;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    // pub fn load(self: *Self, buf: []u8, screenSize: m.Vec2usize) !void
    pub fn load(self: *Self, memory: []u8, screenSize: m.Vec2usize, scale: f32) !void
    {
        std.log.info("App load ({}x{}, {}) ({} MB)", .{screenSize.x, screenSize.y, scale, memory.len / 1024 / 1024});

        self.memory = app.memory.Memory.init(memory, SIZE_PERMANENT, @sizeOf(Self));

        const permanentAllocator = self.memory.permanentAllocator();
        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();
        _ = tempAllocator;

        try self.renderState.load();
        try self.assets.load(permanentAllocator);
        // self.fbAllocator = std.heap.FixedBufferAllocator.init(buf);

        w.glClearColor(0.0, 0.0, 0.0, 0.0);
        w.glEnable(w.GL_DEPTH_TEST);
        w.glDepthFunc(w.GL_LEQUAL);

        w.glEnable(w.GL_BLEND);
        w.glBlendFunc(w.GL_SRC_ALPHA, w.GL_ONE_MINUS_SRC_ALPHA);

        w.setCursorZ("auto");

        // self.renderState = try render.RenderState.init();
        self.fbTexture = 0;
        self.fbDepthRenderbuffer = 0;
        self.fb = 0;

        // self.assets.load(self.fbAllocator.allocator());

        var uriBuf: [64]u8 = undefined;
        const uriLen = w.getUriZ(&uriBuf);
        const uri = uriBuf[0..uriLen];
        self.pageData = try uriToPageData(uri);
        self.screenSizePrev = m.Vec2usize.zero;
        self.scrollYPrev = -1;
        self.timestampMsPrev = 0;
        // self.mouseState = input.MouseState.init();
        // self.keyboardState = input.KeyboardState.init();
        self.activeParallaxSetIndex = PARALLAX_SET_INDEX_START;
        self.parallaxTX = 0;
        self.parallaxIdleTimeMs = 0;
        self.yMaxPrev = 0;

        self.debug = false;

        // _ = try self.assets.register(.{ .Static = asset.Texture.Lut1 },
        //     "images/LUTs/identity.png", defaultTextureWrap, defaultTextureFilter, 2
        // );

        try self.assets.loadTexture(.{.static = asset.Texture.StickerCircle}, &.{
            .path = "images/sticker-circle.png",
            .filter = defaultTextureFilter,
            .wrapMode = defaultTextureWrap,
            // 2
        });
        try self.assets.loadTexture(.{.static = asset.Texture.LoadingGlyphs}, &.{
            .path = "images/loading-glyphs.png",
            .filter = defaultTextureFilter,
            .wrapMode = defaultTextureWrap,
            // 2
        });
        try self.assets.loadTexture(.{.static = asset.Texture.DecalTopLeft}, &.{
            .path = "images/decal-topleft.png",
            .filter = defaultTextureFilter,
            .wrapMode = defaultTextureWrap,
            // 2
        });

        try self.assets.loadTexture(.{.static = asset.Texture.StickerShiny}, &.{
            .path = "images/sticker-shiny.png",
            .filter = defaultTextureFilter,
            .wrapMode = defaultTextureWrap,
            // 5
        });

        switch (self.pageData) {
            .Home => {
                // _ = try self.assets.register(.{ .Static = asset.Texture.LogosAll },
                //     "images/logos-all.png", defaultTextureWrap, defaultTextureFilter, 8
                // );
                // _ = try self.assets.register(.{ .Static = asset.Texture.ProjectSymbols },
                //     "images/project-symbols.png", defaultTextureWrap, defaultTextureFilter, 8
                // );
                // _ = try self.assets.register(.{ .Static = asset.Texture.StickerMainHome },
                //     "images/sticker-main.png", defaultTextureWrap, defaultTextureFilter, 5
                // );
                // _ = try self.assets.register(.{ .Static = asset.Texture.SymbolEye },
                //     "images/symbol-eye.png", defaultTextureWrap, defaultTextureFilter, 5
                // );
                // _ = try self.assets.register(.{ .Static = asset.Texture.YorstoryCompany },
                //     "images/a-yorstory-company.png", defaultTextureWrap, defaultTextureFilter, 5
                // );

                try self.assets.loadTexture(.{.static = asset.Texture.MobileBackground}, &.{
                    .path = "images/mobile/background.png",
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                    // 5
                });
                try self.assets.loadTexture(.{.static = asset.Texture.MobileCrosshair}, &.{
                    .path = "images/mobile/crosshair.png",
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                    // 5
                });
                try self.assets.loadTexture(.{.static = asset.Texture.MobileIcons}, &.{
                    .path = "images/mobile/icons.png",
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                    // 5
                });
                try self.assets.loadTexture(.{.static = asset.Texture.MobileLogo}, &.{
                    .path = "images/mobile/logo-and-stuff.png",
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                    // 5
                });
                try self.assets.loadTexture(.{.static = asset.Texture.MobileYorstoryCompany}, &.{
                    .path = "images/mobile/a-yorstory-company.png",
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                    // 5
                });
            },
            .Entry => {
            },
        }

        const screenSizeF = m.Vec2.initFromVec2usize(screenSize);
        const isVertical = isVerticalAspect(screenSizeF);
        const gridSize = getGridSize(screenSizeF);

        const helveticaBoldUrl = "/fonts/HelveticaNeueLTCom-Bd.ttf";
        const helveticaMediumUrl = "/fonts/HelveticaNeueLTCom-Md.ttf";
        // const helveticaLightUrl = "/fonts/HelveticaNeueLTCom-Lt.ttf";

        const titleFontSize = if (isVertical) fromRefFontSizePx(180, screenSizeF) else gridSize * 4.0;
        const titleKerning = if (isVertical) -gridSize * 0.12 else -gridSize * 0.15;
        const titleLineHeight = titleFontSize * 0.92;
        try self.assets.loadFont(.Title, &.{
            .path = helveticaBoldUrl,
            .atlasSize = 2048,
            .size = titleFontSize,
            .scale = 1.0,
            .kerning = titleKerning,
            .lineHeight = titleLineHeight
        });
        // self.assets.registerStaticFont(asset.Font.Title, helveticaBoldUrl, titleFontSize, 1.0, titleKerning, titleLineHeight) catch |err| {
        //     std.log.err("registerStaticFont failed err={}", .{err});
        // };

        const textFontSize = if (isVertical) fromRefFontSizePx(38, screenSizeF) else gridSize * 0.4;
        const textKerning = 0;
        const textLineHeight = if (isVertical) fromRefFontSizePx(48, screenSizeF) else textFontSize * 1.2;
        try self.assets.loadFont(.Text, &.{
            .path = helveticaMediumUrl,
            .atlasSize = 2048,
            .size = textFontSize,
            .scale = 1.0,
            .kerning = textKerning,
            .lineHeight = textLineHeight,
        });
        // self.assets.registerStaticFont(asset.Font.Text, helveticaMediumUrl, textFontSize, 1.0, textKerning, textLineHeight) catch |err| {
        //     std.log.err("registerStaticFont failed err={}", .{err});
        // };

        // if (!isVertical) {
        //     const categoryFontSize = gridSize * 0.6;
        //     const categoryKerning = 0;
        //     const categoryLineHeight = categoryFontSize;
        //     self.assets.registerStaticFont(asset.Font.Category, helveticaBoldUrl, categoryFontSize, 1.0, categoryKerning, categoryLineHeight) catch |err| {
        //         std.log.err("registerStaticFont failed err={}", .{err});
        //     };

        //     const subtitleFontSize = gridSize * 1.25;
        //     const subtitleKerning = -gridSize * 0.05;
        //     const subtitleLineHeight = subtitleFontSize;
        //     self.assets.registerStaticFont(asset.Font.Subtitle, helveticaLightUrl, subtitleFontSize, 1.0, subtitleKerning, subtitleLineHeight) catch |err| {
        //         std.log.err("registerStaticFont failed err={}", .{err});
        //     };

        //     const numberFontSize = gridSize * 1.8;
        //     const numberKerning = 0;
        //     const numberLineHeight = numberFontSize;
        //     self.assets.registerStaticFont(asset.Font.Number, helveticaBoldUrl, numberFontSize, 1.0, numberKerning, numberLineHeight) catch |err| {
        //         std.log.err("registerStaticFont failed err={}", .{err});
        //     };
        // } else {
        //     const subtitleFontSize = fromRefFontSizePx(18, screenSizeF);
        //     const subtitleKerning = 0.0;
        //     const subtitleLineHeight = fromRefFontSizePx(26, screenSizeF);
        //     self.assets.registerStaticFont(asset.Font.Subtitle, helveticaMediumUrl, subtitleFontSize, 1.0, subtitleKerning, subtitleLineHeight) catch |err| {
        //         std.log.err("registerStaticFont failed err={}", .{err});
        //     };
        // }
    }

    pub fn updateAndRender(state: *Self, screenSize: m.Vec2usize, scrollY: i32, timestampMs: u64) i32
    {
        const screenSizeI = screenSize.toVec2i();
        const screenSizeF = screenSize.toVec2();
        const scrollYF = @intToFloat(f32, scrollY);
        defer {
            state.inputState.mouseState.clear();
            state.inputState.keyboardState.clear();

            state.timestampMsPrev = timestampMs;
            state.scrollYPrev = scrollY;
            state.screenSizePrev = screenSize;
        }

        const keyCodeEscape = 27;
        const keyCodeArrowLeft = 37;
        const keyCodeArrowRight = 39;
        const keyCodeG = 71;

        if (state.pageData == .Entry and state.pageData.Entry.galleryImageIndex != null) {
            const imageCount = getImageCount(state.pageData.Entry);
            if (state.inputState.keyboardState.keyDown(keyCodeEscape)) {
                state.pageData.Entry.galleryImageIndex = null;
            } else if (state.inputState.keyboardState.keyDown(keyCodeArrowLeft)) {
                if (state.pageData.Entry.galleryImageIndex.? == 0) {
                    state.pageData.Entry.galleryImageIndex.? = imageCount - 1;
                } else {
                    state.pageData.Entry.galleryImageIndex.? -= 1;
                }
            } else if (state.inputState.keyboardState.keyDown(keyCodeArrowRight)) {
                state.pageData.Entry.galleryImageIndex.? += 1;
                if (state.pageData.Entry.galleryImageIndex.? >= imageCount) {
                    state.pageData.Entry.galleryImageIndex.? = 0;
                }
            }
        }
        if (state.inputState.keyboardState.keyDown(keyCodeG)) {
            state.debug = !state.debug;
        }

        const deltaMs = if (state.timestampMsPrev > 0) (timestampMs - state.timestampMsPrev) else 0;
        const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

        var tempBufferAllocator = state.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        var renderQueue = tempAllocator.create(app.render.RenderQueue) catch {
            std.log.warn("Failed to allocate RenderQueue", .{});
            return -1;
        };
        renderQueue.load();

        const screenResize = !m.eql(state.screenSizePrev, screenSize);
        if (screenResize) {
            std.log.info("resetting screen framebuffer", .{});
            state.fbTexture = w.createTexture(screenSizeI.x, screenSizeI.y, w.GL_CLAMP_TO_EDGE, w.GL_NEAREST);

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

        // w.glBindFramebuffer(w.GL_FRAMEBUFFER, state.fb);
        w.bindNullFramebuffer();

        w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

        const isVertical = isVerticalAspect(screenSizeF);

        var yMax: i32 = 0;
        if (isVertical) {
            yMax = drawMobile(state, deltaS, scrollYF, screenSizeF, renderQueue, tempAllocator);
        } else {
            // yMax = drawDesktop(state, deltaMs, scrollYF, screenSizeF, renderQueue, tempAllocator);
        }
        defer {
            state.yMaxPrev = yMax;
        }

        renderQueue.render2(&state.renderState, screenSizeF, scrollYF, tempAllocator);
        if (!m.eql(state.screenSizePrev, screenSize) or yMax != state.yMaxPrev) {
            std.log.info("resize, clearing HTML elements", .{});
            w.clearAllEmbeds();
            // renderQueue.renderHtml();
        }

        // w.bindNullFramebuffer();
        // w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);
        // const lut1 = state.assets.getStaticTextureData(asset.Texture.Lut1);
        // // if (lut1.loaded()) {
        //     state.renderState.postProcessState.draw(state.fbTexture, lut1.id, screenSizeF);
        // // }

        // const maxInflight = 8;
        // state.assets.loadQueued(maxInflight);

        return yMax;
        // return true;
    }

    // pub fn deinit(self: Self) void
    // {
    //     self.gpa.deinit();
    // }

    // pub fn allocator(self: *Self) std.mem.Allocator
    // {
    //     return self.fbAllocator.allocator();
    // }
};

const GridImage = struct {
    uri: []const u8,
    title: ?[]const u8,
    goToUri: ?[]const u8,
};

fn drawImageGrid(images: []const GridImage, indexOffset: usize, itemsPerRow: usize, topLeft: m.Vec2, width: f32, spacing: f32, font: asset.Font, fontColor: m.Vec4, state: *App, scrollY: f32, mouseHoverGlobal: *bool, renderQueue: *app.render.RenderQueue, callback: *const fn(*App, GridImage, usize) void) f32
{
    const itemAspect = 1.74;
    const itemWidth = (width - spacing * (@intToFloat(f32, itemsPerRow) - 1)) / @intToFloat(f32, itemsPerRow);
    const itemSize = m.Vec2.init(itemWidth, itemWidth / itemAspect);

    var yMax: f32 = topLeft.y;
    for (images) |img, i| {
        const rowF = @intToFloat(f32, i / itemsPerRow);
        const colF = @intToFloat(f32, i % itemsPerRow);
        const spacingY = if (img.title) |_| spacing * 8 else spacing;
        const itemPos = m.Vec2.init(
            topLeft.x + colF * (itemSize.x + spacing),
            topLeft.y + rowF * (itemSize.y + spacingY)
        );
        if (state.assets.getTextureData(.{.DynamicUrl = img.uri})) |tex| {
            if (tex.loaded()) {
                // const cornerRadius = spacing * 2;
                const cornerRadius = 0;
                renderQueue.quadTex(
                    itemPos, itemSize, DEPTH_GRIDIMAGE, cornerRadius, tex.id, m.Vec4.white
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
                itemPos.y + itemSize.y + spacing * 4
            );
            renderQueue.text2(title, textPos, DEPTH_UI_GENERIC, font, fontColor);

            yMax = std.math.max(yMax, textPos.y);
        }

        if (updateButton(itemPos, itemSize, state.mouseState, scrollY, mouseHoverGlobal)) {
            callback(state, img, indexOffset + i);
        }

        yMax = std.math.max(yMax, itemPos.y + itemSize.y);
    }

    return yMax - topLeft.y;
}

fn getTextureScaledSize(size: m.Vec2usize, screenSize: m.Vec2) m.Vec2
{
    const sizeF = m.Vec2.initFromVec2usize(size);
    const scaleFactor = screenSize.y / refSizeDesktop.y;
    return m.multScalar(sizeF, scaleFactor);
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

fn drawCrosshairCorners(pos: m.Vec2, size: m.Vec2, depth: f32, gridSize: f32, decalTopLeft: *const app.asset_data.TextureData, screenSize: m.Vec2, color: m.Vec4, renderQueue: *app.render.RenderQueue) void
{
    const decalMargin = gridSize * 2;
    const decalSize = getTextureScaledSize(decalTopLeft.size, screenSize);

    const posTL = m.Vec2.init(
        pos.x + decalMargin,
        pos.y + decalMargin,
    );
    const uvOriginTL = m.Vec2.init(0, 0);
    const uvSizeTL = m.Vec2.init(1, 1);
    renderQueue.texQuadColorUvOffset(
        posTL, decalSize, depth, 0, uvOriginTL, uvSizeTL, decalTopLeft, color
    );

    const posTR = m.Vec2.init(
        pos.x + size.x - decalMargin - decalSize.x,
        pos.y + decalMargin,
    );
    const uvOriginTR = m.Vec2.init(1, 0);
    const uvSizeTR = m.Vec2.init(-1, 1);
    renderQueue.texQuadColorUvOffset(
        posTR, decalSize, depth, 0, uvOriginTR, uvSizeTR, decalTopLeft, color
    );

    const posBL = m.Vec2.init(
        pos.x + decalMargin,
        pos.y + size.y - decalMargin - decalSize.y,
    );
    const uvOriginBL = m.Vec2.init(0, 1);
    const uvSizeBL = m.Vec2.init(1, -1);
    renderQueue.texQuadColorUvOffset(
        posBL, decalSize, depth, 0, uvOriginBL, uvSizeBL, decalTopLeft, color
    );

    const posBR = m.Vec2.init(
        pos.x + size.x - decalMargin - decalSize.x,
        pos.y + size.y - decalMargin - decalSize.y,
    );
    const uvOriginBR = m.Vec2.init(1, 1);
    const uvSizeBR = m.Vec2.init(-1, -1);
    renderQueue.texQuadColorUvOffset(
        posBR, decalSize, depth, 0, uvOriginBR, uvSizeBR, decalTopLeft, color
    );
}

fn drawDesktop(state: *App, deltaMs: u64, scrollYF: f32, screenSizeF: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    const colorUi = blk: {
        switch (state.pageData) {
            .Home => {
                break :blk COLOR_YELLOW_HOME;
            },
            .Entry => |entryData| {
                const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
                break :blk pf.colorUi;
            },
        }
    };
    const colorRedSticker = m.Vec4.init(234.0 / 255.0, 65.0 / 255.0, 0.0, 1.0);
    const parallaxMotionMax = screenSizeF.x / 8.0;

    const mousePosF = m.Vec2.initFromVec2i(state.mouseState.pos);
    var mouseHoverGlobal = false;

    const gridSize = getGridSize(screenSizeF);

    const marginX = blk: {
        const maxLandingImageAspect = 2.15;
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - gridSize * 2.0,
            screenSizeF.y - gridSize * 3.0
        );
        const adjustedWidth = std.math.min(landingImageSize.x, landingImageSize.y * maxLandingImageAspect);
        break :blk (landingImageSize.x - adjustedWidth) / 2.0;
    };
    const crosshairMarginX = marginX + gridSize * 5;
    const contentMarginX = marginX + gridSize * 9;

    const decalTopLeft = state.assets.getStaticTextureData(asset.Texture.DecalTopLeft);
    const stickerMain = blk: {
        switch (state.pageData) {
            .Home => break :blk state.assets.getStaticTextureData(asset.Texture.StickerMainHome),
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
    const stickerShiny = state.assets.getStaticTextureData(asset.Texture.StickerShiny);

    const allFontsLoaded = blk: {
        var loaded = true;
        inline for (std.meta.tags(asset.Font)) |f| {
            const fontData = state.assets.getStaticFontData(f);
            loaded = loaded and fontData != null;
        }
        break :blk loaded;
    };
    var allLandingAssetsLoaded = decalTopLeft.loaded() and stickerMain.loaded() and stickerShiny.loaded() and allFontsLoaded;
    if (allLandingAssetsLoaded) {
        const parallaxIndex = blk: {
            switch (state.pageData) {
                .Home => break :blk state.activeParallaxSetIndex,
                .Entry => |entryData| {
                    const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
                    break :blk pf.parallaxIndex;
                },
            }
        };

        // Determine whether the active parallax set is loaded
        var activeParallaxSet = parallax.tryLoadAndGetParallaxSet(&state.assets, parallaxIndex, 5, defaultTextureWrap, defaultTextureFilter);

        // Load later sets
        if (state.pageData == .Home and activeParallaxSet != null) {
            state.parallaxIdleTimeMs += deltaMs;
            const nextSetIndex = (parallaxIndex + 1) % parallax.PARALLAX_SETS.len;
            var nextParallaxSet = parallax.tryLoadAndGetParallaxSet(&state.assets, nextSetIndex, 20, defaultTextureWrap, defaultTextureFilter);
            if (nextParallaxSet) |_| {
                if (state.parallaxIdleTimeMs >= App.PARALLAX_SET_SWAP_SECONDS * 1000) {
                    state.parallaxIdleTimeMs = 0;
                    state.activeParallaxSetIndex = nextSetIndex;
                    activeParallaxSet = nextParallaxSet;
                } else {
                    for (parallax.PARALLAX_SETS) |_, i| {
                        if (parallax.tryLoadAndGetParallaxSet(&state.assets, i, 20, defaultTextureWrap, defaultTextureFilter) == null) {
                            break;
                        }
                    }
                }
            }
        }

        const targetParallaxTX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
        state.parallaxTX = targetParallaxTX;

        if (activeParallaxSet) |parallaxSet| {
            const landingImagePos = m.Vec2.init(
                marginX + gridSize * 1,
                gridSize * 1
            );
            const landingImageSize = m.Vec2.init(
                screenSizeF.x - marginX * 2 - gridSize * 2,
                screenSizeF.y - gridSize * 3
            );

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
                const textureData = state.assets.getTextureData(.{.DynamicUrl = parallaxImage.url}) orelse continue;
                if (!textureData.loaded()) continue;

                const textureDataF = m.Vec2.initFromVec2i(textureData.size);
                const textureSize = m.Vec2.init(
                    landingImageSize.y * textureDataF.x / textureDataF.y,
                    landingImageSize.y
                );
                const parallaxOffsetX = state.parallaxTX * parallaxMotionMax * parallaxImage.factor;

                const imgPos = m.Vec2.init(
                    screenSizeF.x / 2.0 - textureSize.x / 2.0 + parallaxOffsetX,
                    landingImagePos.y
                );
                renderQueue.quadTex(imgPos, textureSize, DEPTH_LANDINGIMAGE, 0.0, textureData.id, m.Vec4.white);
            }
        } else {
            allLandingAssetsLoaded = false;
        }
    }

    if (decalTopLeft.loaded()) {
        const crosshairRectPos = m.Vec2.init(marginX, 0);
        const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, screenSizeF.y);

        drawCrosshairCorners(
            crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
            gridSize, decalTopLeft, screenSizeF, colorUi, renderQueue
        );
    }

    const stickerCircle = state.assets.getStaticTextureData(asset.Texture.StickerCircle);
    const loadingGlyphs = state.assets.getStaticTextureData(asset.Texture.LoadingGlyphs);

    if (allLandingAssetsLoaded) {
        const CategoryInfo = struct {
            name: []const u8,
            uri: ?[]const u8,
        };
        const categories = [_]CategoryInfo {
            .{
                .name = "home",
                .uri = "/",
            },
            .{
                .name = "yorstory",
                .uri = null,
            },
            .{
                .name = "portfolio",
                .uri = null,
            },
            .{
                .name = "contact",
                .uri = null,
            },
        };
        var x = contentMarginX;
        for (categories) |c| {
            const categoryRect = app.render.text2Rect(&state.assets, c.name, asset.Font.Category) orelse break;
            const categorySize = categoryRect.size();
            const categoryPos = m.Vec2.init(x, gridSize * 5.5);
            renderQueue.text2(c.name, categoryPos, DEPTH_UI_GENERIC, asset.Font.Category, colorUi);

            const categoryButtonSize = m.Vec2.init(categorySize.x * 1.2, categorySize.y * 2.0);
            const categoryButtonPos = m.Vec2.init(categoryPos.x - categorySize.x * 0.1, categoryPos.y - categorySize.y);
            if (c.uri) |uri| {
                if (updateButton(categoryButtonPos, categoryButtonSize, state.mouseState, scrollYF, &mouseHoverGlobal)) {
                    w.setUriZ(uri);
                }
            }

            x += categorySize.x + gridSize * 1.4;
        }

        // sticker (main)
        const stickerSize = getTextureScaledSize(stickerMain.size, screenSizeF);
        const stickerPos = m.Vec2.init(
            contentMarginX,
            screenSizeF.y - gridSize * 5 - stickerSize.y
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
            screenSizeF.x - crosshairMarginX - stickerShinySize.x,
            gridSize * 5.0
        );
        renderQueue.quadTex(stickerShinyPos, stickerShinySize, DEPTH_UI_GENERIC, 0, stickerShiny.id, m.Vec4.white);
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
                renderQueue.quad(dotOrigin, dotSize, DEPTH_UI_GENERIC - 0.01, 0, m.Vec4.black);
            }
        }
    }

    {
        // rounded black frame
        const framePos = m.Vec2.init(marginX + gridSize * 1, gridSize * 1);
        const frameSize = m.Vec2.init(
            screenSizeF.x - marginX * 2 - gridSize * 2,
            screenSizeF.y - gridSize * 3,
        );
        renderQueue.roundedFrame(m.Vec2.zero, screenSizeF, DEPTH_UI_OVER1, framePos, frameSize, gridSize, m.Vec4.black);
    }

    const section1Height = screenSizeF.y;

    if (!allLandingAssetsLoaded) {
        return @floatToInt(i32, section1Height);
    }

    // ==== SECOND FRAME ====

    var section2Height: f32 = 0;
    if (state.pageData == .Home) {
        section2Height = screenSizeF.y * 4.0;
        const secondFrameYScrolling = section1Height;
        const secondFrameYStillForever = if (scrollYF >= section1Height) scrollYF else section1Height;
        const secondFrameYStill = blk: {
            if (scrollYF >= section1Height) {
                if (scrollYF <= section1Height + section2Height - screenSizeF.y) {
                    break :blk scrollYF;
                } else {
                    break :blk section1Height + section2Height - screenSizeF.y;
                }
            } else {
                break :blk section1Height;
            }
        };

        // draw moving gradient
        const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
        const gradientPos = m.Vec2.init(0.0, secondFrameYScrolling);
        const gradientSize = m.Vec2.init(screenSizeF.x, section2Height - screenSizeF.y);
        renderQueue.quadGradient(gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0, gradientColor, gradientColor, m.Vec4.black, m.Vec4.black);

        if (decalTopLeft.loaded()) {
            const crosshairRectPos = m.Vec2.init(marginX, secondFrameYStill);
            const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, screenSizeF.y);

            drawCrosshairCorners(
                crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
                gridSize, decalTopLeft, screenSizeF, colorUi, renderQueue
            );
        }

        const yorstoryCompany = state.assets.getStaticTextureData(asset.Texture.YorstoryCompany);
        if (yorstoryCompany.loaded()) {
            const pos = m.Vec2.init(contentMarginX, secondFrameYStill + gridSize * 3.0);
            const size = getTextureScaledSize(yorstoryCompany.size, screenSizeF);
            renderQueue.quadTex(pos, size, DEPTH_UI_GENERIC, 0, yorstoryCompany.id, colorUi);
        }

        const logosAll = state.assets.getStaticTextureData(asset.Texture.LogosAll);
        const symbolEye = state.assets.getStaticTextureData(asset.Texture.SymbolEye);

        const wasPosYCheckpoint1 = section1Height;
        const wasPosYCheckpoint2 = section1Height + screenSizeF.y * 1.0;
        const wasPosBaseY = blk: {
            if (scrollYF <= wasPosYCheckpoint1) {
                break :blk wasPosYCheckpoint1;
            } else if (scrollYF >= wasPosYCheckpoint2) {
                break :blk wasPosYCheckpoint2;
            } else {
                break :blk scrollYF;
            }
        };
        const wasPos = m.Vec2.init(
            contentMarginX - gridSize * 0.3,
            wasPosBaseY + gridSize * 10.8
        );
        const wasText = "We are\nStorytellers.";
        const wasRect = app.render.text2Rect(&state.assets, wasText, asset.Font.Title) orelse unreachable;
        renderQueue.text2(wasText, wasPos, DEPTH_UI_GENERIC, asset.Font.Title, colorUi);

        const wasTextPos1 = m.Vec2.init(
            contentMarginX - gridSize * 0.3,
            wasPos.y - wasRect.min.y + gridSize * 3.2,
        );
        renderQueue.text2("Yorstory is a creative development studio specializing in sequential art. We\nare storytellers with over 20 years of experience in the Television, Film, and\nVideo Game industries.", wasTextPos1, DEPTH_UI_GENERIC, asset.Font.Text, colorUi);
        const wasTextPos2 = m.Vec2.init(
            screenSizeF.x / 2.0,
            wasTextPos1.y,
        );
        renderQueue.text2("Our diverse experience has given us an unparalleled understanding of\nmultiple mediums, giving us the tools to create a cohesive, story-centric vision\nalong with the visuals needed to create a shared understanding between\nmultiple departments and disciplines.", wasTextPos2, DEPTH_UI_GENERIC, asset.Font.Text, colorUi);

        if (symbolEye.loaded()) {
            const eyeSize = getTextureScaledSize(stickerCircle.size, screenSizeF);
            const eyePosY = blk: {
                const eyeCheckpoint1 = section1Height + screenSizeF.y * 0.1;
                const eyeCheckpoint2 = section1Height + screenSizeF.y * 0.5;
                const eyeOffset = gridSize * 6.95;

                if (scrollYF <= eyeCheckpoint1) {
                    break :blk scrollYF - eyeSize.y;
                } else if (scrollYF <= eyeCheckpoint2) {
                    const t = (scrollYF - eyeCheckpoint1) / (eyeCheckpoint2 - eyeCheckpoint1);
                    break :blk scrollYF + m.lerpFloat(-eyeSize.y, eyeOffset, t);
                } else {
                    break :blk wasPosBaseY + eyeOffset;
                }
            };
            const eyePos = m.Vec2.init(
                wasPos.x + gridSize * 10.7,
                eyePosY,
            );
            const eyeStickerColor = m.Vec4.init(0.0, 46.0 / 255.0, 226.0 / 255.0, 1.0);
            // TODO change plus to minus once depth/blend shit is fixed
            const eyeDepth = DEPTH_UI_GENERIC + 0.02;
            const eyeSymbolDepth = DEPTH_UI_GENERIC + 0.01;
            renderQueue.quadTex(eyePos, eyeSize, eyeDepth, 0, stickerCircle.id, eyeStickerColor);
            renderQueue.quadTex(eyePos, eyeSize, eyeSymbolDepth, 0, symbolEye.id, colorUi);
        }

        if (logosAll.loaded()) {
            const logosPosYCheckpoint1 = section1Height + section2Height - screenSizeF.y * 2.0;
            const logosPosYCheckpoint2 = section1Height + section2Height - screenSizeF.y;
            const logosPosBaseY = blk: {
                if (scrollYF <= logosPosYCheckpoint1) {
                    break :blk logosPosYCheckpoint1;
                } else if (scrollYF >= logosPosYCheckpoint2) {
                    break :blk logosPosYCheckpoint2;
                } else {
                    break :blk scrollYF;
                }
            };
            const logosSize = getTextureScaledSize(logosAll.size, screenSizeF);
            const logosPos = m.Vec2.init(
                (screenSizeF.x - logosSize.x) / 2,
                logosPosBaseY + ((screenSizeF.y - logosSize.y) / 2)
            );
            renderQueue.quadTex(logosPos, logosSize, DEPTH_UI_GENERIC, 0, logosAll.id, colorUi);
        }

        {
            // rounded black frame
            const framePos = m.Vec2.init(marginX + gridSize * 1, secondFrameYStill + gridSize * 1);
            const frameSize = m.Vec2.init(
                screenSizeF.x - marginX * 2 - gridSize * 2,
                screenSizeF.y - gridSize * 3,
            );
            renderQueue.roundedFrame(m.Vec2.init(0.0, secondFrameYStill), screenSizeF, DEPTH_UI_OVER1, framePos, frameSize, gridSize, m.Vec4.black);
            _ = secondFrameYStillForever;
        }
    }

    // ==== THIRD FRAME ====

    const CB = struct {
        fn home(theState: *App, image: GridImage, index: usize) void
        {
            _ = theState; _ = index;

            if (image.goToUri) |uri| {
                w.setUriZ(uri);
            }
        }

        fn entry(theState: *App, image: GridImage, index: usize) void
        {
            _ = image;

            if (theState.pageData != .Entry) {
                std.log.err("entry callback, but not an Entry page", .{});
                return;
            }
            if (theState.pageData.Entry.galleryImageIndex == null) {
                theState.pageData.Entry.galleryImageIndex = index;
            }
        }
    };

    var yMax: f32 = section1Height + section2Height;
    const contentSubWidth = screenSizeF.x - contentMarginX * 2;
    switch (state.pageData) {
        .Home => {
        },
        .Entry => |entryData| {
            // content section
            const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];

            const contentHeaderPos = m.Vec2.init(
                contentMarginX,
                yMax + gridSize * 4.0,
            );
            const contentHeaderRect = app.render.text2Rect(&state.assets, pf.contentHeader, asset.Font.Title) orelse unreachable;
            renderQueue.text2(pf.contentHeader, contentHeaderPos, DEPTH_UI_GENERIC, asset.Font.Title, colorUi);

            const contentSubPos = m.Vec2.init(
                contentMarginX,
                contentHeaderPos.y - contentHeaderRect.min.y + gridSize * 3.2,
            );
            const contentSubRect = render.text2Rect(&state.assets, pf.contentDescription, asset.Font.Text) orelse unreachable;
            renderQueue.text2(pf.contentDescription, contentSubPos, DEPTH_UI_GENERIC, asset.Font.Text, colorUi);

            yMax = contentSubPos.y + contentSubRect.size().y + gridSize * 3.0;

            var galleryImages = std.ArrayList(GridImage).init(allocator);

            const x = contentMarginX;
            var yGallery = yMax;
            var indexOffset: usize = 0; // TODO eh...
            for (pf.subprojects) |sub, i| {
                if (sub.name.len > 0 or sub.description.len > 0) {
                    const numberSize = getTextureScaledSize(stickerCircle.size, screenSizeF);
                    const numberPos = m.Vec2.init(
                        contentMarginX - gridSize * 1.4,
                        yGallery - gridSize * 2.4,
                    );
                    // TODO number should be on top, but depth sorting is bad
                    if (stickerCircle.loaded()) {
                        renderQueue.quadTex(
                            numberPos, numberSize, DEPTH_UI_GENERIC + 0.02, 0, stickerCircle.id, colorRedSticker
                        );
                    }
                    const numStr = std.fmt.allocPrint(allocator, "{}", .{i + 1}) catch unreachable;
                    const numberTextPos = m.Vec2.init(
                        numberPos.x + numberSize.x * 0.28,
                        numberPos.y + numberSize.y * 0.75
                    );
                    renderQueue.text2(numStr, numberTextPos, DEPTH_UI_GENERIC + 0.01, asset.Font.Number, m.Vec4.black);

// <<<<<<< HEAD
//                 const subNameRect = app.render.text2Rect(&state.assets, sub.name, asset.Font.Subtitle) orelse unreachable;
//                 renderQueue.text2(sub.name, m.Vec2.init(x, yGallery), DEPTH_UI_GENERIC, asset.Font.Subtitle, colorUi);
//                 yGallery += -subNameRect.min.y + gridSize * 2.0;

//                 const subDescriptionRect = app.render.text2Rect(&state.assets, sub.description, asset.Font.Text) orelse unreachable;
//                 renderQueue.text2(sub.description, m.Vec2.init(x, yGallery), DEPTH_UI_GENERIC, asset.Font.Text, colorUi);
//                 yGallery += -subDescriptionRect.min.y + gridSize * 2.0;
// =======
                    const subNameRect = render.text2Rect(&state.assets, sub.name, asset.Font.Subtitle) orelse unreachable;
                    renderQueue.text2(sub.name, m.Vec2.init(x, yGallery), DEPTH_UI_GENERIC, asset.Font.Subtitle, colorUi);
                    yGallery += -subNameRect.min.y + gridSize * 2.0;

                    const subDescriptionRect = render.text2Rect(&state.assets, sub.description, asset.Font.Text) orelse unreachable;
                    renderQueue.text2(sub.description, m.Vec2.init(x, yGallery), DEPTH_UI_GENERIC, asset.Font.Text, colorUi);
                    yGallery += -subDescriptionRect.min.y + gridSize * 2.0;
                }
// >>>>>>> 75f30b94a8b389768f908a4107e3e0a439fbf391

                galleryImages.clearRetainingCapacity();
                for (sub.images) |img| {
                    galleryImages.append(GridImage {
                        .uri = img,
                        .title = null,
                        .goToUri = null,
                    }) catch |err| {
                        std.log.err("image append failed {}", .{err});
                    };
                }

                const itemsPerRow = 6;
                const topLeft = m.Vec2.init(x, yGallery);
                const spacing = gridSize * 0.25;
                yGallery += drawImageGrid(galleryImages.items, indexOffset, itemsPerRow, topLeft, contentSubWidth, spacing, asset.Font.Text, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.entry);
                yGallery += gridSize * 4.0;
                indexOffset += sub.images.len;
            }

            yMax = yGallery + gridSize * 1;

            // video embed
            if (pf.youtubeId) |youtubeId| {
                const embedWidth = screenSizeF.x - contentMarginX * 2;
                const embedSize = m.Vec2.init(embedWidth, embedWidth / 2.0);
                const embedPos = m.Vec2.init(contentMarginX, yMax);
                renderQueue.embedYoutube(embedPos, embedSize, youtubeId);
                yMax += embedSize.y + gridSize * 4;
            }

            yMax += gridSize * 1;

            if (entryData.galleryImageIndex) |ind| {
                const pos = m.Vec2.init(0.0, scrollYF);
                renderQueue.quad(pos, screenSizeF, DEPTH_UI_OVER2, 0, m.Vec4.init(0.0, 0.0, 0.0, 1.0));

                if (getImageUrlFromIndex(entryData, ind)) |imageUrl| {
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
                            renderQueue.quadTex(imagePos, imageSize, DEPTH_UI_OVER2 - 0.01, 0, imageTex.id, m.Vec4.white);

                            const clickEvents = state.mouseState.clickEvents[0..state.mouseState.numClickEvents];
                            for (clickEvents) |e| {
                                if (e.clickType == .Left and e.down) {
                                    const posF = m.Vec2.initFromVec2i(e.pos);
                                    if (posF.x < (screenSizeF.x - imageSize.x) / 2.0
                                        or posF.x > (screenSizeF.x + imageSize.x) / 2.0
                                        or posF.y < (gridSize * 2.0)
                                        or posF.y > (screenSizeF.y - gridSize * 2.0)) {
                                        state.pageData.Entry.galleryImageIndex = null;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
    }

    const section3Start = yMax;
    const section3YScrolling = section3Start;

    const yorstoryCompany = state.assets.getStaticTextureData(asset.Texture.YorstoryCompany);
    if (yorstoryCompany.loaded()) {
        const pos = m.Vec2.init(contentMarginX, section3YScrolling + gridSize * 3.0);
        const size = getTextureScaledSize(yorstoryCompany.size, screenSizeF);
        renderQueue.quadTex(pos, size, DEPTH_UI_GENERIC, 0, yorstoryCompany.id, colorUi);
    }

    const contentHeaderPos = m.Vec2.init(
        contentMarginX,
        section3Start + gridSize * (11.5 - 0.33),
    );
    const projectsText = if (state.pageData == .Home) "Projects" else "Other Projects";
    renderQueue.text2(projectsText, contentHeaderPos, DEPTH_UI_GENERIC, asset.Font.Title, colorUi);

    var images = std.ArrayList(GridImage).init(allocator);
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

    const projectSymbols = state.assets.getStaticTextureData(asset.Texture.ProjectSymbols);
    if (projectSymbols.loaded()) {
        const symbolsPos = m.Vec2.init(marginX + gridSize * 3.33, section3YScrolling + gridSize * 7.5);
        const symbolsSize = getTextureScaledSize(projectSymbols.size, screenSizeF);
        renderQueue.quadTex(symbolsPos, symbolsSize, DEPTH_UI_GENERIC, 0, projectSymbols.id, colorUi);
    }

    const itemsPerRow = 3;
    const gridTopLeft = m.Vec2.init(
        contentMarginX,
        section3Start + gridSize * 14.0,
    );
    const spacing = gridSize * 0.25;
    const projectGridY = drawImageGrid(images.items, 0, itemsPerRow, gridTopLeft, contentSubWidth, spacing, asset.Font.Text, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.home);

    const section3Height = gridTopLeft.y - section3Start + projectGridY + gridSize * 8.0;

    // draw moving gradient
    const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
    const gradientPos = m.Vec2.init(0.0, section3YScrolling);
    const gradientSize = m.Vec2.init(screenSizeF.x, section3Height * 1.5);
    renderQueue.quadGradient(gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0, gradientColor, gradientColor, m.Vec4.black, m.Vec4.black);

    if (decalTopLeft.loaded()) {
        const crosshairRectPos = m.Vec2.init(marginX, section3YScrolling);
        const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, section3Height - gridSize);

        drawCrosshairCorners(
            crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
            gridSize, decalTopLeft, screenSizeF, colorUi, renderQueue
        );
    }

    {
        // rounded black frame
        const frameTotalSize = m.Vec2.init(screenSizeF.x, section3Height);
        const framePos = m.Vec2.init(marginX + gridSize * 1, section3YScrolling + gridSize * 1);
        const frameSize = m.Vec2.init(
            screenSizeF.x - marginX * 2 - gridSize * 2,
            section3Height - gridSize * 3,
        );
        renderQueue.roundedFrame(m.Vec2.init(0.0, section3YScrolling), frameTotalSize, DEPTH_UI_OVER1, framePos, frameSize, gridSize, m.Vec4.black);
    }

    yMax += section3Height;

    // TODO don't do all the time
    if (mouseHoverGlobal) {
        w.setCursorZ("pointer");
    } else {
        w.setCursorZ("auto");
    }

    if (state.debug) {
        const colorMain = m.Vec4.white;
        const colorHalf = m.Vec4.init(0.5, 0.5, 0.5, 1.0);
        var yDebug: f32 = 0;
        while (yDebug <= yMax) : (yDebug += gridSize) {
            renderQueue.quad(m.Vec2.init(0, yDebug - gridSize * 0.5), m.Vec2.init(screenSizeF.x, 1), DEPTH_UI_ABOVEALL, 0, colorHalf);
            renderQueue.quad(m.Vec2.init(0, yDebug), m.Vec2.init(screenSizeF.x, 1), DEPTH_UI_ABOVEALL, 0, colorMain);
        }
    }

    return @floatToInt(i32, yMax);
}

fn drawMobile(state: *App, deltaS: f32, scrollY: f32, screenSize: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    _ = deltaS;
    _ = scrollY;
    _ = allocator;

    const aspect = screenSize.x / screenSize.y;
    const gridSize = getGridSize(screenSize);

    const quat = m.Quat.initFromEulerAngles(state.inputState.deviceState.angles);
    _ = quat;
    const anglesTarget = state.inputState.deviceState.angles;
    // TODO use something more linear
    state.anglesRef = m.lerp(state.anglesRef, anglesTarget, 0.01);

    const fontTitle = state.assets.getFontData(.Title) orelse return @floatToInt(i32, screenSize.y);
    const fontText = state.assets.getFontData(.Text) orelse return @floatToInt(i32, screenSize.y);
    // const fontsRequired = [_]asset.Font {
    //     asset.Font.Title,
    //     asset.Font.Text,
    // };
    // for (fontsRequired) |font| {
    //     // TODO display loading screen?
    //     // We can't draw/layout page until all fonts are ready.
    //     if (state.assets.getFontData(font) == null) {
    //         return @floatToInt(i32, screenSize.y);
    //     }
    // }

    // if (allFontsLoaded) {
    //     // const anglesRefText = std.fmt.allocPrint(allocator, "x={d:.2}\ny={d:.2}\nz={d:.2}", .{state.anglesRef.x, state.anglesRef.y, state.anglesRef.z}) catch "";
    //     // renderQueue.text2(anglesRefText, m.Vec2.init(50.0, 100.0), 0.0, asset.Font.Text, m.Vec4.one);

    //     const anglesTargetText = std.fmt.allocPrint(allocator, "x={d:.2}\ny={d:.2}\nz={d:.2}", .{anglesTarget.x, anglesTarget.y, anglesTarget.z}) catch "";
    //     renderQueue.text2(anglesTargetText, m.Vec2.init(50.0, 100.0), 0.0, asset.Font.Text, m.Vec4.one);

    //     const relativeUp = m.Quat.rotate(quat, m.Vec3.unitY);
    //     const relativeFront = m.Quat.rotate(quat, m.Vec3.unitZ);
    //     const relativeUpText = std.fmt.allocPrint(allocator, "relative up:\nx={d:.2}\ny={d:.2}\nz={d:.2}", .{relativeUp.x, relativeUp.y, relativeUp.z}) catch "";
    //     renderQueue.text2(relativeUpText, m.Vec2.init(50.0, 400.0), 0.0, asset.Font.Text, m.Vec4.one);
    //     const relativeFrontText = std.fmt.allocPrint(allocator, "relative front:\nx={d:.2}\ny={d:.2}\nz={d:.2}", .{relativeFront.x, relativeFront.y, relativeFront.z}) catch "";
    //     renderQueue.text2(relativeFrontText, m.Vec2.init(50.0, 600.0), 0.0, asset.Font.Text, m.Vec4.one);
    // }

    // ==== FIRST FRAME: LANDING ====

    if (state.assets.getTextureData(.{.static = .MobileBackground})) |bgTex| {
        const bgTexSize = m.Vec2.initFromVec2usize(bgTex.size);
        const bgAspect = bgTexSize.x / bgTexSize.y;
        _ = bgAspect;
        _ = aspect;
        const bgUvBottomLeft = m.Vec2.zero;
        const bgUvSize = m.Vec2.one;
        renderQueue.texQuadColorUvOffset(m.Vec2.zero, screenSize, DEPTH_LANDINGBACKGROUND, 0.0, bgUvBottomLeft, bgUvSize, bgTex, m.Vec4.white);
        // const backgroundSize = if (backgroundAspect < aspect)
        //     m.Vec2.init(screenSize.x, screenSize.x / backgroundAspect)
        //     else
        //     m.Vec2.init(screenSize.y / backgroundSizeF.y * backgroundSizeF.x, screenSize.y);
        // std.log.info("{} vs {}: {}", .{backgroundAspect, aspect, backgroundSize});
        // const backgroundPos = m.Vec2.init(
        //     (screenSize.x - backgroundSize.x) / 2.0,
        //     (screenSize.y - backgroundSize.y) / 2.0,
        // );
        // renderQueue.texQuadColor(backgroundPos, backgroundSize, DEPTH_LANDINGBACKGROUND, 0.0, backgroundTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileYorstoryCompany})) |yorTex| {
        const yorSize = getTextureScaledSize(yorTex.size, screenSize);
        const yorPos = m.Vec2.init(
            gridSize, gridSize * 5.8
        );
        renderQueue.texQuadColor(yorPos, yorSize, DEPTH_UI_GENERIC, 0.0, yorTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileLogo})) |logoTex| {
        const logoSize = getTextureScaledSize(logoTex.size, screenSize);
        const logoPos = m.Vec2.init(
            gridSize, screenSize.y - gridSize * 3.0 - logoSize.y
        );
        renderQueue.texQuadColor(logoPos, logoSize, DEPTH_UI_GENERIC, 0.0, logoTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileCrosshair})) |crosshairTex| {
        const offsetTest = anglesTarget.z / 90.0 * 100.0;
        const crosshairOffset = gridSize * 0.25;
        const pos = m.Vec2.init(-(gridSize + crosshairOffset) + offsetTest, -(gridSize + crosshairOffset));
        const size = m.Vec2.init(screenSize.x + gridSize * 2.0 + crosshairOffset * 2.0, screenSize.y + gridSize * 2.0 + crosshairOffset * 2.0);
        drawCrosshairCorners(pos, size, DEPTH_UI_GENERIC, gridSize, crosshairTex, screenSize, m.Vec4.white, renderQueue);

        const pos2 = m.Vec2.init(-(gridSize + crosshairOffset) + offsetTest, -(gridSize + crosshairOffset) + screenSize.y);
        drawCrosshairCorners(pos2, size, DEPTH_UI_GENERIC, gridSize, crosshairTex, screenSize, m.Vec4.white, renderQueue);
    }

    if (state.assets.getTextureData(.{.static = .MobileIcons})) |iconsTex| {
        const iconsSize = getTextureScaledSize(iconsTex.size, screenSize);
        const iconsPos = m.Vec2.init(screenSize.x - iconsSize.x - gridSize * 1.0, gridSize * 4.0);
        renderQueue.texQuad(iconsPos, iconsSize, DEPTH_UI_GENERIC, 0.0, iconsTex);
    }

    var y = screenSize.y;

    // ==== SECOND FRAME: WE ARE STORYTELLERS ====

    // slightly offset from the crosshair (aligned with the circle)
    const sideMargin = gridSize * 1.0;

    var yWas = y + gridSize * 8.0;
    const wasText = "We are\nStorytellers";
    const wasPos = m.Vec2.init(sideMargin, yWas);
    const wasRect = app.render.textRect(wasText, fontTitle);
    renderQueue.text(wasText, wasPos, DEPTH_UI_GENERIC, fontTitle, COLOR_YELLOW_HOME);
    yWas += wasRect.size().y;

    // TODO what's happening here? why don't I need this extra spacing?
    // yWas += gridSize * 2.0;
    const text1 = "Yorstory is a creative development\nstudio specializing in sequential\nart.";
    const text1Pos = m.Vec2.init(sideMargin, yWas);
    renderQueue.text(text1, text1Pos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
    const text1Rect = app.render.textRect(text1, fontText);
    yWas += text1Rect.size().y;

    yWas += gridSize * 1.0;
    const text2 = "We are storytellers with over\ntwenty years of experience in the\nTelevision, Film, and Video Game\nindustries.";
    const text2Pos = m.Vec2.init(sideMargin, yWas);
    renderQueue.text(text2, text2Pos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
    const text2Rect = app.render.textRect(text2, fontText);
    yWas += text2Rect.size().y;

    y += screenSize.y;

    // ==== THIRD FRAME: PROJECTS ====

    var yProjects = y + gridSize * 1.0;
    for (portfolio.PORTFOLIO_LIST) |pf| {
        const coverAspect = 1.74;
        const coverPos = m.Vec2.init(sideMargin, yProjects);
        const coverWidth = screenSize.x - sideMargin * 2.0;
        const coverSize = m.Vec2.init(coverWidth, coverWidth / coverAspect);
        yProjects += coverSize.y;
        if (state.assets.getTextureData(.{.dynamic = pf.cover})) |tex| {
            // if (tex.loaded()) {
                const cornerRadius = 0;
                renderQueue.texQuadColor(
                    coverPos, coverSize, DEPTH_GRIDIMAGE, cornerRadius, tex, m.Vec4.white
                );
            // }
        } else {
            if (state.assets.getTextureLoadState(.{.dynamic = pf.cover}) == .free) {
                state.assets.loadTexture(.{.dynamic = pf.cover}, &.{
                    .path = pf.cover,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }) catch |err| {
                    std.log.err("Failed to register {s}, err {}", .{pf.cover, err});
                };
            }
            // _ = state.assets.register(.{ .dynamic = pf.cover},
            //     pf.cover, defaultTextureWrap, defaultTextureFilter, 9
            // ) catch |err| {
            //     std.log.err("failed to register {s}, err {}", .{pf.cover, err});
            //     return 0;
            // };
        }

        yProjects += gridSize * 1.0;
        const coverTextPos = m.Vec2.init(sideMargin, yProjects);
        renderQueue.text(pf.title, coverTextPos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
        yProjects += gridSize * 1.5;
    }

    y = yProjects;

    // draw background gradient
    const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
    const gradientPos = m.Vec2.init(0.0, screenSize.y);
    const gradientSize = m.Vec2.init(screenSize.x, y - screenSize.y);
    renderQueue.quadGradient(
        gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0,
        [4]m.Vec4 {m.Vec4.black, m.Vec4.black, gradientColor, gradientColor}
    );

    return @floatToInt(i32, y);
}

// export fn onAnimationFrame(memory: *wasm_app.Memory, outerWidth: c_int, outerHeight: c_int, innerWidth: c_int, innerHeight: c_int, scrollY: c_int, timestampMs: c_int) c_int
// {
//     _ = innerWidth; _ = innerHeight;
//     const screenSizeI = m.Vec2i.init(@intCast(i32, outerWidth), @intCast(i32, outerHeight));
//     const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
//     const scrollYF = @intToFloat(f32, scrollY);

//     var state = memory.castPersistent(App);
//     defer {
//         state.timestampMsPrev = timestampMs;
//         state.scrollYPrev = scrollY;
//         state.screenSizePrev = screenSizeI;
//         state.mouseState.clear();
//         state.keyboardState.clear();
//     }

//     const keyCodeEscape = 27;
//     const keyCodeArrowLeft = 37;
//     const keyCodeArrowRight = 39;
//     const keyCodeG = 71;

//     if (state.pageData == .Entry and state.pageData.Entry.galleryImageIndex != null) {
//         const imageCount = getImageCount(state.pageData.Entry);
//         if (state.keyboardState.keyDown(keyCodeEscape)) {
//             state.pageData.Entry.galleryImageIndex = null;
//         } else if (state.keyboardState.keyDown(keyCodeArrowLeft)) {
//             if (state.pageData.Entry.galleryImageIndex.? == 0) {
//                 state.pageData.Entry.galleryImageIndex.? = imageCount - 1;
//             } else {
//                 state.pageData.Entry.galleryImageIndex.? -= 1;
//             }
//         } else if (state.keyboardState.keyDown(keyCodeArrowRight)) {
//             state.pageData.Entry.galleryImageIndex.? += 1;
//             if (state.pageData.Entry.galleryImageIndex.? >= imageCount) {
//                 state.pageData.Entry.galleryImageIndex.? = 0;
//             }
//         }
//     }
//     if (state.keyboardState.keyDown(keyCodeG)) {
//         state.debug = !state.debug;
//     }

//     const deltaMs = if (state.timestampMsPrev > 0) (timestampMs - state.timestampMsPrev) else 0;
//     const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

//     var tempAllocatorObj = memory.getTransientAllocator();
//     const tempAllocator = tempAllocatorObj.allocator();

//     var renderQueue = app.render.RenderQueue.init(tempAllocator);

//     const screenResize = !m.Vec2i.eql(state.screenSizePrev, screenSizeI);
//     if (screenResize) {
//         std.log.info("resetting screen framebuffer", .{});
//         state.fbTexture = w.createTexture(screenSizeI.x, screenSizeI.y, defaultTextureWrap, w.GL_NEAREST);

//         state.fb = w.glCreateFramebuffer();
//         w.glBindFramebuffer(w.GL_FRAMEBUFFER, state.fb);
//         w.glFramebufferTexture2D(w.GL_FRAMEBUFFER, w.GL_COLOR_ATTACHMENT0, w.GL_TEXTURE_2D, state.fbTexture, 0);

//         state.fbDepthRenderbuffer = w.glCreateRenderbuffer();
//         w.glBindRenderbuffer(w.GL_RENDERBUFFER, state.fbDepthRenderbuffer);
//         w.glRenderbufferStorage(w.GL_RENDERBUFFER, w.GL_DEPTH_COMPONENT16, screenSizeI.x, screenSizeI.y);
//         w.glFramebufferRenderbuffer(w.GL_FRAMEBUFFER, w.GL_DEPTH_ATTACHMENT, w.GL_RENDERBUFFER, state.fbDepthRenderbuffer);
//     }

//     if (state.scrollYPrev != scrollY) {
//     }
//     // TODO
//     // } else {
//     //     return 0;
//     // }

//     w.glBindFramebuffer(w.GL_FRAMEBUFFER, state.fb);

//     w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

//     const isVertical = isVerticalAspect(screenSizeF);

//     var yMax: i32 = 0;
//     if (isVertical) {
//         yMax = drawMobile(state, deltaS, scrollYF, screenSizeF, &renderQueue, tempAllocator);
//     } else {
//         yMax = drawDesktop(state, deltaMs, scrollYF, screenSizeF, &renderQueue, tempAllocator);
//     }
//     defer {
//         state.yMaxPrev = yMax;
//     }

//     renderQueue.render(state.renderState, &state.assets, screenSizeF, scrollYF);
//     if (!m.Vec2i.eql(state.screenSizePrev, screenSizeI) or yMax != state.yMaxPrev) {
//         std.log.info("resize, clearing HTML elements", .{});
//         w.clearAllEmbeds();
//         renderQueue.renderHtml();
//     }

//     w.bindNullFramebuffer();
//     w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);
//     const lut1 = state.assets.getStaticTextureData(asset.Texture.Lut1);
//     // if (lut1.loaded()) {
//         state.renderState.postProcessState.draw(state.fbTexture, lut1.id, screenSizeF);
//     // }

//     const maxInflight = 8;
//     state.assets.loadQueued(maxInflight);

//     return yMax;
// }
