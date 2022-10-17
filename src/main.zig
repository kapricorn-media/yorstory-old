const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm.zig");

var _state: State = undefined;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    w.log(message_level, scope, format, args);
}

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
    IconContact,
    IconHome,
    IconPortfolio,
    IconWork,
};

const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    fn init(url: []const u8, wrapMode: c_uint) !Self
    {
        const texture = w.createTexture(&url[0], url.len, wrapMode);
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
        self.textures[@enumToInt(Texture.IconContact)] = try TextureData.init(
            "images/icon-contact.png", w.GL_CLAMP_TO_EDGE
        );
        self.textures[@enumToInt(Texture.IconHome)] = try TextureData.init(
            "images/icon-home.png", w.GL_CLAMP_TO_EDGE
        );
        self.textures[@enumToInt(Texture.IconPortfolio)] = try TextureData.init(
            "images/icon-portfolio.png", w.GL_CLAMP_TO_EDGE
        );
        self.textures[@enumToInt(Texture.IconWork)] = try TextureData.init(
            "images/icon-work.png", w.GL_CLAMP_TO_EDGE
        );
        return self;
    }

    fn getTextureData(self: Self, texture: Texture) TextureData
    {
        return self.textures[@enumToInt(texture)];
    }
};

const QuadState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    offsetPosUniLoc: c_int,
    scalePosUniLoc: c_int,
    colorUniLoc: c_int,

    const positions = [6]m.Vec2 {
        m.Vec2.init(0.0, 0.0),
        m.Vec2.init(0.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 0.0),
        m.Vec2.init(0.0, 0.0),
    };

    const vert = @embedFile("shaders/quad.vert");
    const frag = @embedFile("shaders/quad.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const positionBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, positionBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, @alignCast(4, &positions[0].x), positions.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        const a_position = "a_position";
        const positionAttrLoc = w.glGetAttribLocation(programId, &a_position[0], a_position.len);
        if (positionAttrLoc == -1) {
            return error.MissingAttrLoc;
        }

        const u_offsetPos = "u_offsetPos";
        const offsetPosUniLoc = w.glGetUniformLocation(programId, &u_offsetPos[0], u_offsetPos.len);
        if (offsetPosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_scalePos = "u_scalePos";
        const scalePosUniLoc = w.glGetUniformLocation(programId, &u_scalePos[0], u_scalePos.len);
        if (scalePosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_color = "u_color";
        const colorUniLoc = w.glGetUniformLocation(programId, &u_color[0], u_color.len);
        if (colorUniLoc == -1) {
            return error.MissingUniformLoc;
        }

        return Self {
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = positionAttrLoc,

            .offsetPosUniLoc = offsetPosUniLoc,
            .scalePosUniLoc = scalePosUniLoc,
            .colorUniLoc = colorUniLoc,
        };
    }

    pub fn drawQuadNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        color: m.Vec4) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform2fv(self.offsetPosUniLoc, posNdc.x, posNdc.y);
        w.glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        w.glUniform4fv(self.colorUniLoc, color.x, color.y, color.z, color.w);

        w.glDrawArrays(w.GL_TRIANGLES, 0, positions.len);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawQuadNdc(posNdc, scaleNdc, color);
    }
};

const QuadTextureState = struct {
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

    const vert = @embedFile("shaders/quadTexture.vert");
    const frag = @embedFile("shaders/quadTexture.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const positionBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, positionBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, @alignCast(4, &positions[0].x), positions.len * 2, w.GL_STATIC_DRAW);

        const uvBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, uvBuffer);
        // UVs are the same as positions
        w.glBufferData(w.GL_ARRAY_BUFFER, @alignCast(4, &positions[0].x), positions.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        const a_position = "a_position";
        const positionAttrLoc = w.glGetAttribLocation(programId, &a_position[0], a_position.len);
        if (positionAttrLoc == -1) {
            return error.MissingAttrLoc;
        }
        const a_uv = "a_uv";
        const uvAttrLoc = w.glGetAttribLocation(programId, &a_uv[0], a_uv.len);
        if (uvAttrLoc == -1) {
            return error.MissingAttrLoc;
        }

        const u_offsetPos = "u_offsetPos";
        const offsetPosUniLoc = w.glGetUniformLocation(programId, &u_offsetPos[0], u_offsetPos.len);
        if (offsetPosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_scalePos = "u_scalePos";
        const scalePosUniLoc = w.glGetUniformLocation(programId, &u_scalePos[0], u_scalePos.len);
        if (scalePosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_offsetUv = "u_offsetUv";
        const offsetUvUniLoc = w.glGetUniformLocation(programId, &u_offsetUv[0], u_offsetUv.len);
        if (offsetUvUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_scaleUv = "u_scaleUv";
        const scaleUvUniLoc = w.glGetUniformLocation(programId, &u_scaleUv[0], u_scaleUv.len);
        if (scaleUvUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_sampler = "u_sampler";
        const samplerUniLoc = w.glGetUniformLocation(programId, &u_sampler[0], u_sampler.len);
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
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);
        w.glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.uvBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform2fv(self.offsetPosUniLoc, posNdc.x, posNdc.y);
        w.glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        w.glUniform2fv(self.offsetUvUniLoc, uvOffset.x, uvOffset.y);
        w.glUniform2fv(self.scaleUvUniLoc, uvScale.x, uvScale.y);

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, texture);
        w.glUniform1i(self.samplerUniLoc, 0);

        w.glDrawArrays(w.GL_TRIANGLES, 0, positions.len);
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

const QuadDraw = struct {
    posNdc: m.Vec2,
    scaleNdc: m.Vec2,
    color: m.Vec4,
};

const QuadTextureDraw = struct {
    posNdc: m.Vec2,
    scaleNdc: m.Vec2,
    uvOffset: m.Vec2,
    uvScale: m.Vec2,
    texture: c_uint,
};

const RenderState = struct {
    quadState: QuadState,
    quadTexState: QuadTextureState,

    const Self = @This();

    pub fn init() !Self
    {
        return Self {
            .quadState = try QuadState.init(),
            .quadTexState = try QuadTextureState.init(),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.quadState.deinit();
        self.quadTexState.deinit();
    }
};

const State = struct {
    renderState: RenderState,

    assets: Assets,

    screenSizePrev: m.Vec2i,
    scrollYPrev: c_int,
    timestampMsPrev: c_int,

    const Self = @This();

    pub fn init() !Self
    {
        return Self {
            .renderState = try RenderState.init(),

            .assets = try Assets.init(),

            .screenSizePrev = m.Vec2i.zero,
            .scrollYPrev = -1,
            .timestampMsPrev = 0,
        };
    }

    pub fn deinit(self: Self) void
    {
        self.gpa.deinit();
    }
};

pub fn createText(text: []const u8, topLeft: m.Vec2i, fontSize: c_int) void
{
    w.addText(&text[0], text.len, topLeft.x, topLeft.y, fontSize);
}

export fn onInit() void
{
    _state = State.init() catch |err| {
        std.log.err("State init failed, err {}", .{err});
        return;
    };
    std.log.info("onInit", .{});
    // std.log.info("{}", .{_state});

    w.glClearColor(1.0, 1.0, 1.0, 1.0);
    w.glEnable(w.GL_DEPTH_TEST);
    w.glDepthFunc(w.GL_LEQUAL);

    w.glEnable(w.GL_BLEND);
    w.glBlendFunc(w.GL_SRC_ALPHA, w.GL_ONE_MINUS_SRC_ALPHA);
}

export fn onClick(x: c_int, y: c_int) void
{
    _ = x; _ = y;
}

export fn onAnimationFrame(width: c_int, height: c_int, scrollY: c_int, timestampMs: c_int) c_int
{
    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
    const halfScreenSizeF = m.Vec2.divScalar(screenSizeF, 2.0);
    _ = halfScreenSizeF;

    const deltaMs = if (_state.timestampMsPrev > 0) (timestampMs - _state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;
    _ = deltaS;

    const totalHeight = height * 2;

    var drawText = false;
    if (!m.Vec2i.eql(_state.screenSizePrev, screenSizeI)) {
        _state.screenSizePrev = screenSizeI;

        std.log.info("resize, clearing text", .{});
        w.clearAllText();
        drawText = true;
    }
    if (_state.scrollYPrev != scrollY) {
        _state.scrollYPrev = scrollY;
    } else {
        return totalHeight;
    }

    const gridSize = std.math.round(screenSizeF.y * 0.04);
    _ = gridSize;

    w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

    const colorBlack = m.Vec4.init(0.0, 0.0, 0.0, 1.0);

    const p1 = m.Vec2.init(50, screenSizeF.y - 100 + @intToFloat(f32, scrollY));
    const s1 = m.Vec2.init(50, 50);
    _state.renderState.quadState.drawQuad(p1, s1, colorBlack, screenSizeF);

    const p2 = m.Vec2.init(50, screenSizeF.y - 400 + @intToFloat(f32, scrollY));
    const s2 = m.Vec2.init(800, 1);
    _state.renderState.quadState.drawQuad(p2, s2, colorBlack, screenSizeF);

    const pos = m.Vec2.init(screenSizeF.x - 100, 50 + @intToFloat(f32, scrollY));
    const size = m.Vec2.init(50, 50);
    _state.renderState.quadState.drawQuad(pos, size, colorBlack, screenSizeF);

    const p3 = m.Vec2.init(0, screenSizeF.y - screenSizeF.y * 1.5 + @intToFloat(f32, scrollY));
    const s3 = m.Vec2.init(screenSizeF.x, 1);
    _state.renderState.quadState.drawQuad(p3, s3, colorBlack, screenSizeF);

    if (drawText) {
        createText("hello, world", m.Vec2i.init(100, 400), 32);
        createText("F gello, yorlf", m.Vec2i.init(0, @floatToInt(i32, screenSizeF.y * 1.5)), 32);
    }

    _state.timestampMsPrev = timestampMs;

    return totalHeight;
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
