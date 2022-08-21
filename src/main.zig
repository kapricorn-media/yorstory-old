const std = @import("std");

const m = @import("math.zig");

// Shaders
extern fn consoleMessage(isError: bool, messagePtr: *const u8, messageLen: c_uint) void;
extern fn compileShader(source: *const u8 , len:  c_uint, type: c_uint) c_uint;
extern fn linkShaderProgram(vertexShaderId: c_uint, fragmentShaderId: c_uint) c_uint;
extern fn createTexture(imgUrlPtr: *const u8, imgUrlLen: c_uint, wrapMode: c_uint) c_uint;

// GL
extern fn glClear(_: c_uint) void;
extern fn glClearColor(_: f32, _: f32, _: f32, _: f32) void;

extern fn glEnable(_: c_uint) void;

extern fn glBlendFunc(_: c_uint, _: c_uint) void;
extern fn glDepthFunc(_: c_uint) void;

extern fn glGetAttribLocation(_: c_uint, _: *const u8, _: c_uint) c_int;
extern fn glGetUniformLocation(_: c_uint, _: *const u8, _: c_uint) c_int;

extern fn glUniform1i(_: c_int, _: c_int) void;
extern fn glUniform2fv(_: c_int, _: f32, _: f32) void;
extern fn glUniform3fv(_: c_int, _: f32, _: f32, _: f32) void;
extern fn glUniform4fv(_: c_int, _: f32, _: f32, _: f32, _: f32) void;

extern fn glCreateBuffer() c_uint;
extern fn glBindBuffer(_: c_uint, _: c_uint) void;
extern fn glBufferData(_: c_uint, _: *const f32,  _: c_uint, _: c_uint) void;

extern fn glUseProgram(_: c_uint) void;

extern fn glEnableVertexAttribArray(_: c_uint) void;
extern fn glVertexAttribPointer(_: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint) void;

extern fn glActiveTexture(_: c_uint) void;
extern fn glBindTexture(_: c_uint, _: c_uint) void;

extern fn glDrawArrays(_: c_uint, _: c_uint, _: c_uint) void;

// Identifier constants pulled from WebGLRenderingContext
const GL_VERTEX_SHADER: c_uint = 35633;
const GL_FRAGMENT_SHADER: c_uint = 35632;
const GL_ARRAY_BUFFER: c_uint = 34962;
const GL_TRIANGLES: c_uint = 4;
const GL_STATIC_DRAW: c_uint = 35044;
const GL_f32: c_uint = 5126;

const GL_DEPTH_TEST: c_uint = 2929;
const GL_LEQUAL: c_uint = 515;

const GL_BLEND: c_uint = 3042;
const GL_SRC_ALPHA: c_uint = 770;
const GL_ONE_MINUS_SRC_ALPHA: c_uint = 771;

const GL_COLOR_BUFFER_BIT: c_uint = 16384;
const GL_DEPTH_BUFFER_BIT: c_uint = 256;

const GL_TEXTURE_2D: c_uint = 3553;
const GL_TEXTURE0: c_uint = 33984;

const GL_REPEAT: c_uint = 10497;
const GL_CLAMP_TO_EDGE: c_uint = 33071;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = scope;

    var buf: [2048]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, format, args) catch {
        const errMsg = "bufPrint failed for format: " ++ format;
        consoleMessage(true, &errMsg[0], errMsg.len);
        return;
    };

    const isError = switch (message_level) {
        .err, .warn => true, 
        .info, .debug => false,
    };
    consoleMessage(isError, &message[0], message.len);
}

var _state: State = undefined;

fn floatPosToNdc(pos: f32, canvas: f32) f32
{
    return pos / canvas * 2.0 - 1.0;
}

fn floatSizeToNdc(size: f32, canvas: f32) f32
{
    return size / canvas * 2.0;
}

fn posToNdc(comptime T: type, pos: T, canvas: T) T
{
    switch (T) {
        f32 => {
            return floatPosToNdc(pos, canvas);
        },
        m.Vec2 => {
            return m.Vec2.init(
                floatPosToNdc(pos.x, canvas.x),
                floatPosToNdc(pos.y, canvas.y)
            );
        },
        m.Vec3 => {
            return m.Vec3.init(
                floatPosToNdc(pos.x, canvas.x),
                floatPosToNdc(pos.y, canvas.y),
                floatPosToNdc(pos.z, canvas.z)
            );
        },
        else => @compileError("nope"),
    }
}

fn sizeToNdc(comptime T: type, size: T, canvas: T) T
{
    switch (T) {
        f32 => {
            return floatSizeToNdc(size, canvas);
        },
        m.Vec2 => {
            return m.Vec2.init(
                floatSizeToNdc(size.x, canvas.x),
                floatSizeToNdc(size.y, canvas.y)
            );
        },
        m.Vec3 => {
            return m.Vec3.init(
                floatSizeToNdc(size.x, canvas.x),
                floatSizeToNdc(size.y, canvas.y),
                floatSizeToNdc(size.z, canvas.z)
            );
        },
        else => @compileError("nope"),
    }
}

const Texture = enum(usize) {
    Logo,
    ScrollingText,
    Icons,
    Categories,
};

const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    fn init(url: []const u8, wrapMode: c_uint) !Self
    {
        const texture = createTexture(&url[0], url.len, wrapMode);
        if (texture == -1) {
            return error.createTextureFailed;
        }

        return Self {
            .id = texture,
            .size = m.Vec2i.zero, // set later when the image is loaded from URL
        };
    }

    fn loaded(self: Self) bool
    {
        return !m.Vec2i.eql(self.size, m.Vec2i.zero);
    }
};

const Assets = struct {
    const numTextures = @typeInfo(Texture).Enum.fields.len;

    textures: [numTextures]TextureData,

    const Self = @This();

    fn init() !Self
    {
        var self: Self = undefined;
        self.textures[@enumToInt(Texture.Logo)] = try TextureData.init(
            "images/logo.png", GL_CLAMP_TO_EDGE
        );
        self.textures[@enumToInt(Texture.ScrollingText)] = try TextureData.init(
            "images/scrolling-text.png",GL_REPEAT
        );
        self.textures[@enumToInt(Texture.Icons)] = try TextureData.init(
            "images/icons.png", GL_CLAMP_TO_EDGE
        );
        self.textures[@enumToInt(Texture.Categories)] = try TextureData.init(
            "images/categories.png", GL_CLAMP_TO_EDGE
        );
        return self;
    }

    fn getTextureData(self: Self, texture: Texture) TextureData
    {
        return self.textures[@enumToInt(texture)];
    }
};

const State = struct {
    timestampMsPrev: c_int,
    quad: QuadState,
    assets: Assets,
    scrollingTextY: f32,

    const Self = @This();

    pub fn init() !Self
    {
        return Self {
            .timestampMsPrev = 0,
            .quad = try QuadState.init(),
            .assets = try Assets.init(),
            .scrollingTextY = 0.0,
        };
    }

    pub fn deinit(self: Self) void
    {
        self.gpa.deinit();
    }
};

const QuadState = struct {
    positionBuffer: c_uint,
    uvBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,
    uvAttrLoc: c_int,

    offsetPosUniLoc: c_int,
    scalePosUniLoc: c_int,
    offsetUvUniLoc: c_int,
    scaleUvUniLoc: c_int,
    samplerUniLoc: c_int,

    const positions = [6]m.Vec2 {
        m.Vec2.init(0.0, 0.0),
        m.Vec2.init(0.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 0.0),
        m.Vec2.init(0.0, 0.0),
    };

    const vertQuad = @embedFile("shaders/quad.vert");
    const fragQuad = @embedFile("shaders/quad.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = compileShader(&vertQuad[0], vertQuad.len, GL_VERTEX_SHADER);
        const fragQuadId = compileShader(&fragQuad[0], fragQuad.len, GL_FRAGMENT_SHADER);

        const positionBuffer = glCreateBuffer();
        glBindBuffer(GL_ARRAY_BUFFER, positionBuffer);
        glBufferData(GL_ARRAY_BUFFER, &positions[0].x, positions.len * 2, GL_STATIC_DRAW);

        const uvBuffer = glCreateBuffer();
        glBindBuffer(GL_ARRAY_BUFFER, uvBuffer);
        // UVs are the same as positions
        glBufferData(GL_ARRAY_BUFFER, &positions[0].x, positions.len * 2, GL_STATIC_DRAW);

        const programId = linkShaderProgram(vertQuadId, fragQuadId);

        const a_position = "a_position";
        const positionAttrLoc = glGetAttribLocation(programId, &a_position[0], a_position.len);
        if (positionAttrLoc == -1) {
            return error.MissingAttrLoc;
        }
        const a_uv = "a_uv";
        const uvAttrLoc = glGetAttribLocation(programId, &a_uv[0], a_uv.len);
        if (uvAttrLoc == -1) {
            return error.MissingAttrLoc;
        }

        const u_offsetPos = "u_offsetPos";
        const offsetPosUniLoc = glGetUniformLocation(programId, &u_offsetPos[0], u_offsetPos.len);
        if (offsetPosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_scalePos = "u_scalePos";
        const scalePosUniLoc = glGetUniformLocation(programId, &u_scalePos[0], u_scalePos.len);
        if (scalePosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_offsetUv = "u_offsetUv";
        const offsetUvUniLoc = glGetUniformLocation(programId, &u_offsetUv[0], u_offsetUv.len);
        if (offsetUvUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_scaleUv = "u_scaleUv";
        const scaleUvUniLoc = glGetUniformLocation(programId, &u_scaleUv[0], u_scaleUv.len);
        if (scaleUvUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_sampler = "u_sampler";
        const samplerUniLoc = glGetUniformLocation(programId, &u_sampler[0], u_sampler.len);
        if (samplerUniLoc == -1) {
            return error.MissingUniformLoc;
        }

        return Self {
            .positionBuffer = positionBuffer,
            .uvBuffer = uvBuffer,

            .programId = programId,

            .positionAttrLoc = positionAttrLoc,
            .uvAttrLoc = uvAttrLoc,

            .offsetPosUniLoc = offsetPosUniLoc,
            .scalePosUniLoc = scalePosUniLoc,
            .offsetUvUniLoc = offsetUvUniLoc,
            .scaleUvUniLoc = scaleUvUniLoc,
            .samplerUniLoc = samplerUniLoc,
        };
    }

    pub fn drawQuadNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint) void
    {
        glUseProgram(self.programId);

        glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        glBindBuffer(GL_ARRAY_BUFFER, self.positionBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, GL_f32, 0, 0, 0);
        glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        glBindBuffer(GL_ARRAY_BUFFER, self.uvBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, GL_f32, 0, 0, 0);

        glUniform2fv(self.offsetPosUniLoc, posNdc.x, posNdc.y);
        glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        glUniform2fv(self.offsetUvUniLoc, uvOffset.x, uvOffset.y);
        glUniform2fv(self.scaleUvUniLoc, uvScale.x, uvScale.y);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture);
        glUniform1i(self.samplerUniLoc, 0);

        glDrawArrays(GL_TRIANGLES, 0, positions.len);
    }

    pub fn drawQuadUvOffset(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawQuadNdc(posNdc, scaleNdc, uvOffset, uvScale, texture);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        texture: c_uint,
        screenSize: m.Vec2) void
    {
        self.drawQuadUvOffset(posPixels, scalePixels, m.Vec2.zero, m.Vec2.one, texture, screenSize);
    }
};

export fn onInit() void
{
    _state = State.init() catch |err| {
        std.log.err("State init failed, err {}", .{err});
        return;
    };
    std.log.info("{}", .{_state});

    glClearColor(1.0, 1.0, 1.0, 1.0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

export fn onAnimationFrame(width: c_int, height: c_int, timestampMs: c_int) void
{
    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
    const halfScreenSizeF = m.Vec2.divScalar(screenSizeF, 2.0);
    _ = halfScreenSizeF;

    const deltaMs = if (_state.timestampMsPrev > 0) (timestampMs - _state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

    const speed = 0.2;
    _state.scrollingTextY += speed * deltaS;
    while (_state.scrollingTextY < -1.0) {
        _state.scrollingTextY += 1.0;
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    const textureLogo = _state.assets.getTextureData(Texture.Logo);
    const textureText = _state.assets.getTextureData(Texture.ScrollingText);
    const textureIcons = _state.assets.getTextureData(Texture.Icons);
    const textureCategories = _state.assets.getTextureData(Texture.Categories);

    if (!textureLogo.loaded() or !textureText.loaded() or !textureIcons.loaded() or !textureCategories.loaded()) {
        std.log.info("skipping, not loaded", .{});
        return;
    }

    const logoSizeF = m.Vec2.initFromVec2i(textureLogo.size); // original pixel size
    const logoWidthPixels = screenSizeF.x * 0.34;
    const logoAspect = logoSizeF.x / logoSizeF.y;
    const logoSizePixels = m.Vec2.init(logoWidthPixels, logoWidthPixels / logoAspect);
    const logoPosPixels = m.Vec2.sub(halfScreenSizeF, m.Vec2.divScalar(logoSizePixels, 2.0));

    const textSizeF = m.Vec2.initFromVec2i(textureText.size); // original pixel size
    const textWidthPixels = logoWidthPixels * textSizeF.x / logoSizeF.x;
    const textAspect = textSizeF.x / textSizeF.y;
    const textSizePixels = m.Vec2.init(textWidthPixels, textWidthPixels / textAspect);
    const textPosPixels = m.Vec2.init(
        halfScreenSizeF.x + logoSizePixels.x * 0.07,
        halfScreenSizeF.y - logoSizePixels.y * 0.15
    );

    const fracSize = (screenSizeF.y - textPosPixels.y) / textSizePixels.y;
    const num = @floatToInt(u32, fracSize) + 1;
    var i: u32 = 0;
    while (i < num) : (i += 1) {
        const offsetY = textSizePixels.y * @intToFloat(f32, i);
        const pos = m.Vec2.add(textPosPixels, m.Vec2.init(0.0, offsetY));
        const uvOffset = m.Vec2.init(0.0, _state.scrollingTextY);
        const uvScale = m.Vec2.one;
        _state.quad.drawQuadUvOffset(
            pos, textSizePixels, uvOffset, uvScale, textureText.id, screenSizeF
        );
    }

    const iconsSizeF = m.Vec2.initFromVec2i(textureIcons.size); // original pixel size
    const iconsWidthPixels = 0.75 * logoWidthPixels * iconsSizeF.x / logoSizeF.x;
    const iconsAspect = iconsSizeF.x / iconsSizeF.y;
    const iconsSizePixels = m.Vec2.init(iconsWidthPixels, iconsWidthPixels / iconsAspect);
    const iconsPosPixels = m.Vec2.init(
        halfScreenSizeF.x + logoSizePixels.x * 0.07,
        textPosPixels.y - iconsSizePixels.y,
    );
    _state.quad.drawQuad(iconsPosPixels, iconsSizePixels, textureIcons.id, screenSizeF);

    _state.quad.drawQuad(logoPosPixels, logoSizePixels, textureLogo.id, screenSizeF);

    const categoriesSizeF = m.Vec2.initFromVec2i(textureCategories.size); // original pixel size
    const categoriesWidthPixels = logoWidthPixels * categoriesSizeF.x / logoSizeF.x;
    const categoriesAspect = categoriesSizeF.x / categoriesSizeF.y;
    const categoriesSizePixels = m.Vec2.init(categoriesWidthPixels, categoriesWidthPixels / categoriesAspect);
    const categoriesPosPixels = m.Vec2.init(
        halfScreenSizeF.x - categoriesSizePixels.x / 2.0,
        halfScreenSizeF.y - logoSizePixels.y * 1.5,
    );
    _state.quad.drawQuad(categoriesPosPixels, categoriesSizePixels, textureCategories.id, screenSizeF);

    _state.timestampMsPrev = timestampMs;
}

export fn onTextureLoaded(textureId: c_uint, width: c_int, height: c_int) void
{
    std.log.info("onTextureLoaded {}: {} x {}", .{textureId, width, height});

    var found = false;
    for (_state.assets.textures) |*texture| {
        if (texture.id == textureId) {
            texture.size = m.Vec2i.init(width, height);
            found = true;
            break;
        }
    }

    if (!found) {
        std.log.err("onTextureLoaded not found!", .{});
    }
}
