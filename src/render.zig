const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");
const asset = @import("asset.zig"); // TODO: STOGLY

pub fn text2Rect(assets: anytype, text: []const u8, font: asset.Font) m.Rect
{
    const fontData = assets.getStaticFontData(font);

    var pos = m.Vec2.zero;
    var min = m.Vec2.zero;
    var max = m.Vec2.zero;
    for (text) |c| {
        if (c == '\n') {
            pos.y -= fontData.lineHeight;
            pos.x = 0.0;

            min.y = std.math.min(min.y, pos.y);
            max.y = std.math.max(max.y, pos.y);
        } else {
            const charData = fontData.charData[c];
            pos.x += charData.advanceX + fontData.kerning;

            min.x = std.math.min(min.x, pos.x);
            max.x = std.math.max(max.x, pos.x + charData.size.x);
            min.y = std.math.min(min.y, pos.y);
            max.y = std.math.max(max.y, pos.y + charData.size.y);

            const offsetPos = m.Vec2.add(pos, charData.offset);
            min.x = std.math.min(min.x, offsetPos.x);
            max.x = std.math.max(max.x, offsetPos.x + charData.size.x);
            min.y = std.math.min(min.y, offsetPos.y);
            max.y = std.math.max(max.y, offsetPos.y + charData.size.y);
        }
    }

    return m.Rect.init(min, max);
}

const TextAlign = enum {
    Left,
    Center,
    Right,
};

fn textAlignToString(textAlign: TextAlign) []const u8
{
    return switch (textAlign) {
        .Left => "left",
        .Center => "center",
        .Right => "right",
    };
}

const POS_UNIT_SQUARE: [6]m.Vec2 align(4) = [6]m.Vec2 {
    m.Vec2.init(0.0, 0.0),
    m.Vec2.init(0.0, 1.0),
    m.Vec2.init(1.0, 1.0),
    m.Vec2.init(1.0, 1.0),
    m.Vec2.init(1.0, 0.0),
    m.Vec2.init(0.0, 0.0),
};

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

fn getAttributeLocation(programId: c_uint, attributeName: []const u8) !c_int
{
    const loc = w.glGetAttribLocation(programId, &attributeName[0], attributeName.len);
    return if (loc == -1) error.MissingAttributeLoc else loc;
}

fn getUniformLocation(programId: c_uint, uniformName: []const u8) !c_int
{
    const loc = w.glGetUniformLocation(programId, &uniformName[0], uniformName.len);
    return if (loc == -1) error.MissingUniformLoc else loc;
}

const QuadState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    posPixelsDepthUniLoc: c_int,
    sizePixelsUniLoc: c_int,
    screenSizeUniLoc: c_int,
    colorTLUniLoc: c_int,
    colorTRUniLoc: c_int,
    colorBLUniLoc: c_int,
    colorBRUniLoc: c_int,
    cornerRadiusUniLoc: c_int,

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
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        return Self {
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = try getAttributeLocation(programId, "a_position"),

            .posPixelsDepthUniLoc = try getUniformLocation(programId, "u_posPixelsDepth"),
            .sizePixelsUniLoc = try getUniformLocation(programId, "u_sizePixels"),
            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
            .colorTLUniLoc = try getUniformLocation(programId, "u_colorTL"),
            .colorTRUniLoc = try getUniformLocation(programId, "u_colorTR"),
            .colorBLUniLoc = try getUniformLocation(programId, "u_colorBL"),
            .colorBRUniLoc = try getUniformLocation(programId, "u_colorBR"),
            .cornerRadiusUniLoc = try getUniformLocation(programId, "u_cornerRadius"),
        };
    }

    pub fn drawQuadGradient(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        colorTL: m.Vec4,
        colorTR: m.Vec4,
        colorBL: m.Vec4,
        colorBR: m.Vec4,
        screenSize: m.Vec2) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.posPixelsDepthUniLoc, posPixels.x, posPixels.y, depth);
        w.glUniform2fv(self.sizePixelsUniLoc, scalePixels.x, scalePixels.y);
        w.glUniform2fv(self.screenSizeUniLoc, screenSize.x, screenSize.y);
        w.glUniform4fv(self.colorTLUniLoc, colorTL.x, colorTL.y, colorTL.z, colorTL.w);
        w.glUniform4fv(self.colorTRUniLoc, colorTR.x, colorTR.y, colorTR.z, colorTR.w);
        w.glUniform4fv(self.colorBLUniLoc, colorBL.x, colorBL.y, colorBL.z, colorBL.w);
        w.glUniform4fv(self.colorBRUniLoc, colorBR.x, colorBR.y, colorBR.z, colorBR.w);
        w.glUniform1fv(self.cornerRadiusUniLoc, cornerRadius);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        self.drawQuadGradient(posPixels, scalePixels, depth, cornerRadius, color, color, color, color, screenSize);
    }
};

const QuadTextureState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    posPixelsDepthUniLoc: c_int,
    sizePixelsUniLoc: c_int,
    screenSizeUniLoc: c_int,
    offsetUvUniLoc: c_int,
    scaleUvUniLoc: c_int,
    samplerUniLoc: c_int,
    colorUniLoc: c_int,
    cornerRadiusUniLoc: c_int,

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
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        return Self {
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = try getAttributeLocation(programId, "a_position"),

            .posPixelsDepthUniLoc = try getUniformLocation(programId, "u_posPixelsDepth"),
            .sizePixelsUniLoc = try getUniformLocation(programId, "u_sizePixels"),
            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
            .offsetUvUniLoc = try getUniformLocation(programId, "u_offsetUv"),
            .scaleUvUniLoc = try getUniformLocation(programId, "u_scaleUv"),
            .samplerUniLoc = try getUniformLocation(programId, "u_sampler"),
            .colorUniLoc = try getUniformLocation(programId, "u_color"),
            .cornerRadiusUniLoc = try getUniformLocation(programId, "u_cornerRadius"),
        };
    }

    pub fn drawQuadUvOffset(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.posPixelsDepthUniLoc, posPixels.x, posPixels.y, depth);
        w.glUniform2fv(self.sizePixelsUniLoc, scalePixels.x, scalePixels.y);
        w.glUniform2fv(self.screenSizeUniLoc, screenSize.x, screenSize.y);
        w.glUniform2fv(self.offsetUvUniLoc, uvOffset.x, uvOffset.y);
        w.glUniform2fv(self.scaleUvUniLoc, uvScale.x, uvScale.y);
        w.glUniform4fv(self.colorUniLoc, color.x, color.y, color.z, color.w);
        w.glUniform1fv(self.cornerRadiusUniLoc, cornerRadius);

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, texture);
        w.glUniform1i(self.samplerUniLoc, 0);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        texture: c_uint,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        self.drawQuadUvOffset(
            posPixels, scalePixels, depth, cornerRadius, m.Vec2.zero, m.Vec2.one, texture, color, screenSize
        );
    }
};

const RoundedFrameState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    offsetPosUniLoc: c_int,
    scalePosUniLoc: c_int,
    framePosUniLoc: c_int,
    frameSizeUniLoc: c_int,
    cornerRadiusUniLoc: c_int,
    colorUniLoc: c_int,
    screenSizeUniLoc: c_int,

    const vert = @embedFile("shaders/roundedFrame.vert");
    const frag = @embedFile("shaders/roundedFrame.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const positionBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, positionBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        return Self {
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = try getAttributeLocation(programId, "a_position"),

            .offsetPosUniLoc = try getUniformLocation(programId, "u_offsetPos"),
            .scalePosUniLoc = try getUniformLocation(programId, "u_scalePos"),
            .framePosUniLoc = try getUniformLocation(programId, "u_framePos"),
            .frameSizeUniLoc = try getUniformLocation(programId, "u_frameSize"),
            .cornerRadiusUniLoc = try getUniformLocation(programId, "u_cornerRadius"),
            .colorUniLoc = try getUniformLocation(programId, "u_color"),
            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
        };
    }

    pub fn drawFrameNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        depth: f32,
        framePosPixels: m.Vec2,
        frameSizePixels: m.Vec2,
        cornerRadius: f32,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.offsetPosUniLoc, posNdc.x, posNdc.y, depth);
        w.glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        w.glUniform2fv(self.framePosUniLoc, framePosPixels.x, framePosPixels.y);
        w.glUniform2fv(self.frameSizeUniLoc, frameSizePixels.x, frameSizePixels.y);
        w.glUniform1fv(self.cornerRadiusUniLoc, cornerRadius);
        w.glUniform4fv(self.colorUniLoc, color.x, color.y, color.z, color.w);
        w.glUniform2fv(self.screenSizeUniLoc, screenSize.x, screenSize.y);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawFrame(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        framePosPixels: m.Vec2,
        frameSizePixels: m.Vec2,
        cornerRadius: f32,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawFrameNdc(
            posNdc, scaleNdc, depth, framePosPixels, frameSizePixels, cornerRadius,
            color, screenSize
        );
    }
};

const TextState = struct {
    posBuffer: c_uint,
    posPixelsBuffer: c_uint,
    sizePixelsBuffer: c_uint,
    uvOffsetBuffer: c_uint,

    programId: c_uint,

    posAttrLoc: c_int,
    posPixelsAttrLoc: c_int,
    sizePixelsAttrLoc: c_int,
    uvOffsetAttrLoc: c_int,

    screenSizeUniLoc: c_int,
    depthUniLoc: c_int,
    samplerUniLoc: c_int,
    colorUniLoc: c_int,

    const maxInstances = 1024;
    const vert = @embedFile("shaders/text.vert");
    const frag = @embedFile("shaders/text.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const posBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, posBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const posPixelsBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, posPixelsBuffer);
        w.glBufferData3(w.GL_ARRAY_BUFFER, maxInstances * @sizeOf(m.Vec2), w.GL_DYNAMIC_DRAW);

        const sizePixelsBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, sizePixelsBuffer);
        w.glBufferData3(w.GL_ARRAY_BUFFER, maxInstances * @sizeOf(m.Vec2), w.GL_DYNAMIC_DRAW);

        const uvOffsetBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, uvOffsetBuffer);
        w.glBufferData3(w.GL_ARRAY_BUFFER, maxInstances * @sizeOf(m.Vec2), w.GL_DYNAMIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        return Self {
            .posBuffer = posBuffer,
            .posPixelsBuffer = posPixelsBuffer,
            .sizePixelsBuffer = sizePixelsBuffer,
            .uvOffsetBuffer = uvOffsetBuffer,

            .programId = programId,

            .posAttrLoc = try getAttributeLocation(programId, "a_pos"),
            .posPixelsAttrLoc = try getAttributeLocation(programId, "a_posPixels"),
            .sizePixelsAttrLoc = try getAttributeLocation(programId, "a_sizePixels"),
            .uvOffsetAttrLoc = try getAttributeLocation(programId, "a_uvOffset"),

            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
            .depthUniLoc = try getUniformLocation(programId, "u_depth"),
            .samplerUniLoc = try getUniformLocation(programId, "u_sampler"),
            .colorUniLoc = try getUniformLocation(programId, "u_color"),
        };
    }
};

const PostProcessState = struct {
    positionBuffer: c_uint,
    uvBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,
    uvAttrLoc: c_int,

    samplerUniLoc: c_int,
    screenSizeUniLoc: c_int,
    lutSamplerUniLoc: c_int,

    const vert = @embedFile("shaders/post.vert");
    const frag = @embedFile("shaders/post.frag");

    const Self = @This();

    pub fn init() !Self
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const positionBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, positionBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const uvBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, uvBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        return Self {
            .positionBuffer = positionBuffer,
            .uvBuffer = uvBuffer,

            .programId = programId,

            .positionAttrLoc = try getAttributeLocation(programId, "a_position"),
            .uvAttrLoc = try getAttributeLocation(programId, "a_uv"),

            .samplerUniLoc = try getUniformLocation(programId, "u_sampler"),
            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
            .lutSamplerUniLoc = try getUniformLocation(programId, "u_lutSampler"),
        };
    }

    pub fn draw(self: Self, texture: c_uint, lutTexture: c_uint, screenSize: m.Vec2) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);
        w.glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.uvBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform2fv(self.screenSizeUniLoc, screenSize.x, screenSize.y);

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, texture);
        w.glUniform1i(self.samplerUniLoc, 0);

        w.glActiveTexture(w.GL_TEXTURE1);
        w.glBindTexture(w.GL_TEXTURE_2D, lutTexture);
        w.glUniform1i(self.lutSamplerUniLoc, 1);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }
};

pub const RenderState = struct {
    quadState: QuadState,
    quadTexState: QuadTextureState,
    roundedFrameState: RoundedFrameState,
    textState: TextState,
    postProcessState: PostProcessState,

    const Self = @This();

    pub fn init() !Self
    {
        return Self {
            .quadState = try QuadState.init(),
            .quadTexState = try QuadTextureState.init(),
            .roundedFrameState = try RoundedFrameState.init(),
            .textState = try TextState.init(),
            .postProcessState = try PostProcessState.init(),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.quadState.deinit();
        self.quadTexState.deinit();
        self.roundedFrameState.deinit();
        self.textState.deinit();
        self.postProcessState.deinit();
    }
};

fn colorToHexString(buf: []u8, color: m.Vec4) ![]u8
{
    // TODO custom byte color type?
    const r = @floatToInt(u8, std.math.round(color.x * 255.0));
    const g = @floatToInt(u8, std.math.round(color.y * 255.0));
    const b = @floatToInt(u8, std.math.round(color.z * 255.0));
    const a = @floatToInt(u8, std.math.round(color.w * 255.0));

    return std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{r, g, b, a});
}

const RenderEntryQuad = struct {
    topLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    cornerRadius: f32,
    colorTL: m.Vec4,
    colorTR: m.Vec4,
    colorBL: m.Vec4,
    colorBR: m.Vec4,
};

const RenderEntryQuadTex = struct {
    topLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    cornerRadius: f32,
    uvOffset: m.Vec2,
    uvScale: m.Vec2,
    textureId: c_uint,
    color: m.Vec4,
};

const RenderEntryRoundedFrame = struct {
    topLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    frameTopLeft: m.Vec2,
    frameSize: m.Vec2,
    cornerRadius: f32,
    color: m.Vec4,
};

const RenderEntryText = struct {
    text: []const u8,
    baselineLeft: m.Vec2,
    depth: f32,
    font: asset.Font,
    color: m.Vec4,
};

const RenderEntryTextLine = struct {
    text: []const u8,
    baselineLeft: m.Vec2,
    fontSize: f32,
    letterSpacing: f32,
    color: m.Vec4,
    fontFamily: []const u8
};

const RenderEntryTextBox = struct {
    text: []const u8,
    topLeft: m.Vec2,
    width: f32,
    fontSize: f32,
    lineHeight: f32,
    letterSpacing: f32,
    color: m.Vec4,
    fontFamily: []const u8,
    textAlign: TextAlign,
};

const RenderEntryYoutubeEmbed = struct {
    topLeft: m.Vec2,
    size: m.Vec2,
    youtubeId: []const u8,
};

fn posTopLeftToBottomLeft(pos: m.Vec2, size: m.Vec2, screenSize: m.Vec2, scrollY: f32) m.Vec2
{
    return m.Vec2.init(
        pos.x,
        screenSize.y - pos.y - size.y + scrollY,
    );
}

pub const RenderQueue = struct
{
    quads: std.ArrayList(RenderEntryQuad),
    quadTexs: std.ArrayList(RenderEntryQuadTex),
    roundedFrames: std.ArrayList(RenderEntryRoundedFrame),
    texts: std.ArrayList(RenderEntryText),
    textLines: std.ArrayList(RenderEntryTextLine),
    textBoxes: std.ArrayList(RenderEntryTextBox),
    youtubeEmbeds: std.ArrayList(RenderEntryYoutubeEmbed),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self
    {
        return Self {
            .quads = std.ArrayList(RenderEntryQuad).init(allocator),
            .quadTexs = std.ArrayList(RenderEntryQuadTex).init(allocator),
            .roundedFrames = std.ArrayList(RenderEntryRoundedFrame).init(allocator),
            .texts = std.ArrayList(RenderEntryText).init(allocator),
            .textLines = std.ArrayList(RenderEntryTextLine).init(allocator),
            .textBoxes = std.ArrayList(RenderEntryTextBox).init(allocator),
            .youtubeEmbeds = std.ArrayList(RenderEntryYoutubeEmbed).init(allocator),
        };
    }

    pub fn deinit(self: Self) void
    {
        self.quads.deinit();
        self.quadTexs.deinit();
        self.roundedFrames.deinit();
        self.texts.deinit();
        self.textLines.deinit();
        self.textBoxes.deinit();
        self.youtubeEmbeds.deinit();
    }

    pub fn quadGradient(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, cornerRadius: f32, colorTL: m.Vec4, colorTR: m.Vec4, colorBL: m.Vec4, colorBR: m.Vec4) void
    {
        (self.quads.addOne() catch return).* = RenderEntryQuad {
            .topLeft = topLeft,
            .size = size,
            .depth = depth,
            .cornerRadius = cornerRadius,
            .colorTL = colorTL,
            .colorTR = colorTR,
            .colorBL = colorBL,
            .colorBR = colorBR,
        };
    }

    pub fn quad(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, cornerRadius: f32, color: m.Vec4) void
    {
        self.quadGradient(topLeft, size, depth, cornerRadius, color, color, color, color);
    }

    pub fn quadTexUvOffset(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, cornerRadius: f32, uvOffset: m.Vec2, uvScale: m.Vec2, textureId: c_uint, color: m.Vec4) void
    {
        (self.quadTexs.addOne() catch return).* = RenderEntryQuadTex {
            .topLeft = topLeft,
            .size = size,
            .depth = depth,
            .cornerRadius = cornerRadius,
            .uvOffset = uvOffset,
            .uvScale = uvScale,
            .textureId = textureId,
            .color = color,
        };
    }

    pub fn quadTex(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, cornerRadius: f32, textureId: c_uint, color: m.Vec4) void
    {
        self.quadTexUvOffset(topLeft, size, depth, cornerRadius, m.Vec2.zero, m.Vec2.one, textureId, color);
    }

    pub fn roundedFrame(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, frameTopLeft: m.Vec2, frameSize: m.Vec2, cornerRadius: f32, color: m.Vec4) void
    {
        (self.roundedFrames.addOne() catch return).* = RenderEntryRoundedFrame {
            .topLeft = topLeft,
            .size = size,
            .depth = depth,
            .frameTopLeft = frameTopLeft,
            .frameSize = frameSize,
            .cornerRadius = cornerRadius,
            .color = color,
        };
    }

    pub fn text2(self: *Self, text: []const u8, baselineLeft: m.Vec2, depth: f32, font: asset.Font, color: m.Vec4) void
    {
        (self.texts.addOne() catch return).* = RenderEntryText {
            .text = text,
            .baselineLeft = baselineLeft,
            .depth = depth,
            .font = font,
            .color = color,
        };
    }

    pub fn textLine(self: *Self, text: []const u8, baselineLeft: m.Vec2, fontSize: f32, letterSpacing: f32, color: m.Vec4, fontFamily: []const u8) void
    {
        (self.textLines.addOne() catch return).* = RenderEntryTextLine {
            .text = text,
            .baselineLeft = baselineLeft,
            .fontSize = fontSize,
            .letterSpacing = letterSpacing,
            .color = color,
            .fontFamily = fontFamily,
        };
    }

    pub fn textBox(self: *Self, text: []const u8, topLeft: m.Vec2, width: f32, fontSize: f32, lineHeight: f32, letterSpacing: f32, color: m.Vec4, fontFamily: []const u8, textAlign: TextAlign) void
    {
        (self.textBoxes.addOne() catch return).* = RenderEntryTextBox {
            .text = text,
            .topLeft = topLeft,
            .width = width,
            .fontSize = fontSize,
            .lineHeight = lineHeight,
            .letterSpacing = letterSpacing,
            .color = color,
            .fontFamily = fontFamily,
            .textAlign = textAlign,
        };
    }

    pub fn embedYoutube(self: *Self, topLeft: m.Vec2, size: m.Vec2, youtubeId: []const u8) void
    {
        (self.youtubeEmbeds.addOne() catch return).* = RenderEntryYoutubeEmbed {
            .topLeft = topLeft,
            .size = size,
            .youtubeId = youtubeId,
        };
    }

    pub fn renderShapes(self: Self, renderState: RenderState, assets: anytype, screenSize: m.Vec2, scrollY: f32) void
    {
        // TODO fix depth/blend madness

        for (self.quads.items) |e| {
            const posBottomLeft = posTopLeftToBottomLeft(e.topLeft, e.size, screenSize, scrollY);
            renderState.quadState.drawQuadGradient(posBottomLeft, e.size, e.depth, e.cornerRadius, e.colorTL, e.colorTR, e.colorBL, e.colorBR, screenSize);
        }
        for (self.quadTexs.items) |e| {
            const posBottomLeft = posTopLeftToBottomLeft(e.topLeft, e.size, screenSize, scrollY);
            renderState.quadTexState.drawQuadUvOffset(posBottomLeft, e.size, e.depth, e.cornerRadius, e.uvOffset, e.uvScale, e.textureId, e.color, screenSize);
        }

        w.glUseProgram(renderState.textState.programId);
        w.glUniform2fv(renderState.textState.screenSizeUniLoc, screenSize.x, screenSize.y);

        w.glEnableVertexAttribArray(@intCast(c_uint, renderState.textState.posAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, renderState.textState.posBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, renderState.textState.posAttrLoc), 2, w.GL_f32, 0, 0, 0);

        var buffer: [TextState.maxInstances]m.Vec2 = undefined;
        for (self.texts.items) |e| {
            const fontData = assets.getStaticFontData(e.font);
            const n = std.math.min(e.text.len, TextState.maxInstances);
            const text = e.text[0..n];

            var pos = m.Vec2.init(e.baselineLeft.x, screenSize.y - e.baselineLeft.y + scrollY);
            for (text) |c, i| {
                if (c == '\n') {
                    buffer[i] = m.Vec2.zero;
                    pos.y -= fontData.lineHeight;
                    pos.x = e.baselineLeft.x;
                } else {
                    const charData = fontData.charData[c];
                    buffer[i] = m.Vec2.add(pos, charData.offset);
                    pos.x += charData.advanceX + fontData.kerning; // TODO nah
                }
            }
            w.glEnableVertexAttribArray(@intCast(c_uint, renderState.textState.posPixelsAttrLoc));
            w.glBindBuffer(w.GL_ARRAY_BUFFER, renderState.textState.posPixelsBuffer);
            w.glBufferSubData(w.GL_ARRAY_BUFFER, 0, &buffer[0].x, n * 2);
            w.glVertexAttribPointer(@intCast(c_uint, renderState.textState.posPixelsAttrLoc), 2, w.GL_f32, 0, 0, 0);
            w.vertexAttribDivisorANGLE(renderState.textState.posPixelsAttrLoc, 1);

            for (text) |c, i| {
                if (c == '\n') {
                    buffer[i] = m.Vec2.zero;
                } else {
                    const charData = fontData.charData[c];
                    buffer[i] = charData.size;
                }
            }
            w.glEnableVertexAttribArray(@intCast(c_uint, renderState.textState.sizePixelsAttrLoc));
            w.glBindBuffer(w.GL_ARRAY_BUFFER, renderState.textState.sizePixelsBuffer);
            w.glBufferSubData(w.GL_ARRAY_BUFFER, 0, &buffer[0].x, n * 2);
            w.glVertexAttribPointer(@intCast(c_uint, renderState.textState.sizePixelsAttrLoc), 2, w.GL_f32, 0, 0, 0);
            w.vertexAttribDivisorANGLE(renderState.textState.sizePixelsAttrLoc, 1);

            for (text) |c, i| {
                if (c == '\n') {
                    buffer[i] = m.Vec2.zero;
                } else {
                    const charData = fontData.charData[c];
                    buffer[i] = charData.uvOffset;
                }
            }
            w.glEnableVertexAttribArray(@intCast(c_uint, renderState.textState.uvOffsetAttrLoc));
            w.glBindBuffer(w.GL_ARRAY_BUFFER, renderState.textState.uvOffsetBuffer);
            w.glBufferSubData(w.GL_ARRAY_BUFFER, 0, &buffer[0].x, n * 2);
            w.glVertexAttribPointer(@intCast(c_uint, renderState.textState.uvOffsetAttrLoc), 2, w.GL_f32, 0, 0, 0);
            w.vertexAttribDivisorANGLE(renderState.textState.uvOffsetAttrLoc, 1);

            w.glUniform1fv(renderState.textState.depthUniLoc, e.depth);
            w.glUniform4fv(renderState.textState.colorUniLoc, e.color.x, e.color.y, e.color.z, e.color.w);

            w.glActiveTexture(w.GL_TEXTURE0);
            w.glBindTexture(w.GL_TEXTURE_2D, fontData.textureId);
            w.glUniform1i(renderState.textState.samplerUniLoc, 0);

            w.drawArraysInstancedANGLE(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len, n);
        }

        w.vertexAttribDivisorANGLE(0, 0);
        w.vertexAttribDivisorANGLE(1, 0);
        w.vertexAttribDivisorANGLE(2, 0);
        w.vertexAttribDivisorANGLE(3, 0);
        w.vertexAttribDivisorANGLE(4, 0);

        for (self.roundedFrames.items) |e| {
            const posBottomLeft = posTopLeftToBottomLeft(e.topLeft, e.size, screenSize, scrollY);
            const frameBottomLeft = posTopLeftToBottomLeft(e.frameTopLeft, e.frameSize, screenSize, scrollY);
            renderState.roundedFrameState.drawFrame(
                posBottomLeft, e.size, e.depth, frameBottomLeft, e.frameSize, e.cornerRadius, e.color, screenSize
            );
        }
    }

    pub fn renderText(self: Self) void
    {
        var buf: [32]u8 = undefined;
        for (self.textLines.items) |e| {
            const hexColor = colorToHexString(&buf, e.color) catch continue;
            w.addTextLine(
                &e.text[0], e.text.len,
                @floatToInt(c_int, e.baselineLeft.x), @floatToInt(c_int, e.baselineLeft.y),
                @floatToInt(c_int, e.fontSize), e.letterSpacing,
                &hexColor[0], hexColor.len, &e.fontFamily[0], e.fontFamily.len
            );
        }
        for (self.textBoxes.items) |e| {
            const textAlign = textAlignToString(e.textAlign);
            const hexColor = colorToHexString(&buf, e.color) catch continue;
            w.addTextBox(
                &e.text[0], e.text.len,
                @floatToInt(c_int, e.topLeft.x), @floatToInt(c_int, e.topLeft.y),
                @floatToInt(c_int, e.width),
                @floatToInt(c_int, e.fontSize), @floatToInt(c_int, e.lineHeight), e.letterSpacing,
                &hexColor[0], hexColor.len, &e.fontFamily[0], e.fontFamily.len,
                &textAlign[0], textAlign.len
            );
        }
    }

    pub fn renderEmbeds(self: Self) void
    {
        for (self.youtubeEmbeds.items) |e| {
            w.addYoutubeEmbed(
                @floatToInt(c_int, e.topLeft.x), @floatToInt(c_int, e.topLeft.y),
                @floatToInt(c_int, e.size.x), @floatToInt(c_int, e.size.y),
                &e.youtubeId[0], e.youtubeId.len
            );
        }
    }
};
