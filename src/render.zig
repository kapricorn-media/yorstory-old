const std = @import("std");

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");

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

const QuadState = struct {
    positionBuffer: c_uint,
    uvBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,
    uvAttrLoc: c_int,

    offsetPosUniLoc: c_int,
    scalePosUniLoc: c_int,
    colorTLUniLoc: c_int,
    colorTRUniLoc: c_int,
    colorBLUniLoc: c_int,
    colorBRUniLoc: c_int,

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

        const uvBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, uvBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

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
        const u_colorTL = "u_colorTL";
        const colorTLUniLoc = w.glGetUniformLocation(programId, &u_colorTL[0], u_colorTL.len);
        if (colorTLUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_colorTR = "u_colorTR";
        const colorTRUniLoc = w.glGetUniformLocation(programId, &u_colorTR[0], u_colorTR.len);
        if (colorTRUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_colorBL= "u_colorBL";
        const colorBLUniLoc = w.glGetUniformLocation(programId, &u_colorBL[0], u_colorBL.len);
        if (colorBLUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_colorBR = "u_colorBR";
        const colorBRUniLoc = w.glGetUniformLocation(programId, &u_colorBR[0], u_colorBR.len);
        if (colorBRUniLoc == -1) {
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
            .colorTLUniLoc = colorTLUniLoc,
            .colorTRUniLoc = colorTRUniLoc,
            .colorBLUniLoc = colorBLUniLoc,
            .colorBRUniLoc = colorBRUniLoc,
        };
    }

    pub fn drawQuadNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        depth: f32,
        colorTL: m.Vec4,
        colorTR: m.Vec4,
        colorBL: m.Vec4,
        colorBR: m.Vec4) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);
        w.glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.uvBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.offsetPosUniLoc, posNdc.x, posNdc.y, depth);
        w.glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        w.glUniform4fv(self.colorTLUniLoc, colorTL.x, colorTL.y, colorTL.z, colorTL.w);
        w.glUniform4fv(self.colorTRUniLoc, colorTR.x, colorTR.y, colorTR.z, colorTR.w);
        w.glUniform4fv(self.colorBLUniLoc, colorBL.x, colorBL.y, colorBL.z, colorBL.w);
        w.glUniform4fv(self.colorBRUniLoc, colorBR.x, colorBR.y, colorBR.z, colorBR.w);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawQuadGradient(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        colorTL: m.Vec4,
        colorTR: m.Vec4,
        colorBL: m.Vec4,
        colorBR: m.Vec4,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawQuadNdc(posNdc, scaleNdc, depth, colorTL, colorTR, colorBL, colorBR);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        self.drawQuadGradient(posPixels, scalePixels, depth, color, color, color, color, screenSize);
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

        const uvBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, uvBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

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
        const u_color = "u_color";
        const colorUniLoc = w.glGetUniformLocation(programId, &u_color[0], u_color.len);
        if (colorUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_cornerRadius = "u_cornerRadius";
        const cornerRadiusUniLoc = w.glGetUniformLocation(programId, &u_cornerRadius[0], u_cornerRadius.len);
        if (cornerRadiusUniLoc == -1) {
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
            .colorUniLoc = colorUniLoc,
            .cornerRadiusUniLoc = cornerRadiusUniLoc,
        };
    }

    pub fn drawQuadNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        depth: f32,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint,
        color: m.Vec4) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);
        w.glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.uvBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.offsetPosUniLoc, posNdc.x, posNdc.y, depth);
        w.glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        w.glUniform2fv(self.offsetUvUniLoc, uvOffset.x, uvOffset.y);
        w.glUniform2fv(self.scaleUvUniLoc, uvScale.x, uvScale.y);
        w.glUniform4fv(self.colorUniLoc, color.x, color.y, color.z, color.w);
        w.glUniform1fv(self.cornerRadiusUniLoc, 0.0);

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, texture);
        w.glUniform1i(self.samplerUniLoc, 0);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawQuadUvOffset(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawQuadNdc(posNdc, scaleNdc, depth, uvOffset, uvScale, texture, color);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        texture: c_uint,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        self.drawQuadUvOffset(
            posPixels, scalePixels, depth, m.Vec2.zero, m.Vec2.one, texture, color, screenSize
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
        const u_framePos = "u_framePos";
        const framePosUniLoc = w.glGetUniformLocation(programId, &u_framePos[0], u_framePos.len);
        if (framePosUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_frameSize = "u_frameSize";
        const frameSizeUniLoc = w.glGetUniformLocation(programId, &u_frameSize[0], u_frameSize.len);
        if (frameSizeUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_cornerRadius = "u_cornerRadius";
        const cornerRadiusUniLoc = w.glGetUniformLocation(programId, &u_cornerRadius[0], u_cornerRadius.len);
        if (cornerRadiusUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_color = "u_color";
        const colorUniLoc = w.glGetUniformLocation(programId, &u_color[0], u_color.len);
        if (colorUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_screenSize = "u_screenSize";
        const screenSizeUniLoc = w.glGetUniformLocation(programId, &u_screenSize[0], u_screenSize.len);
        if (screenSizeUniLoc == -1) {
            return error.MissingUniformLoc;
        }

        return Self {
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = positionAttrLoc,

            .offsetPosUniLoc = offsetPosUniLoc,
            .scalePosUniLoc = scalePosUniLoc,
            .framePosUniLoc = framePosUniLoc,
            .frameSizeUniLoc = frameSizeUniLoc,
            .cornerRadiusUniLoc = cornerRadiusUniLoc,
            .colorUniLoc = colorUniLoc,
            .screenSizeUniLoc = screenSizeUniLoc,
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

const PostProcessState = struct {
    positionBuffer: c_uint,
    uvBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,
    uvAttrLoc: c_int,

    samplerUniLoc: c_int,
    screenSizeUniLoc: c_int,

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

        const u_sampler = "u_sampler";
        const samplerUniLoc = w.glGetUniformLocation(programId, &u_sampler[0], u_sampler.len);
        if (samplerUniLoc == -1) {
            return error.MissingUniformLoc;
        }
        const u_screenSize = "u_screenSize";
        const screenSizeUniLoc = w.glGetUniformLocation(programId, &u_screenSize[0], u_screenSize.len);
        if (screenSizeUniLoc == -1) {
            return error.MissingUniformLoc;
        }

        return Self {
            .positionBuffer = positionBuffer,
            .uvBuffer = uvBuffer,

            .programId = programId,

            .positionAttrLoc = positionAttrLoc,
            .uvAttrLoc = uvAttrLoc,

            .samplerUniLoc = samplerUniLoc,
            .screenSizeUniLoc = screenSizeUniLoc,
        };
    }

    pub fn draw(self: Self, texture: c_uint, screenSize: m.Vec2) void
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

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }
};

pub const RenderState = struct {
    quadState: QuadState,
    quadTexState: QuadTextureState,
    roundedFrameState: RoundedFrameState,
    postProcessState: PostProcessState,

    const Self = @This();

    pub fn init() !Self
    {
        return Self {
            .quadState = try QuadState.init(),
            .quadTexState = try QuadTextureState.init(),
            .roundedFrameState = try RoundedFrameState.init(),
            .postProcessState = try PostProcessState.init(),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.quadState.deinit();
        self.quadTexState.deinit();
        self.roundedFrameState.deinit();
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
    colorTL: m.Vec4,
    colorTR: m.Vec4,
    colorBL: m.Vec4,
    colorBR: m.Vec4,
};

const RenderEntryQuadTex = struct {
    topLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
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
    textLines: std.ArrayList(RenderEntryTextLine),
    textBoxes: std.ArrayList(RenderEntryTextBox),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self
    {
        return Self {
            .quads = std.ArrayList(RenderEntryQuad).init(allocator),
            .quadTexs = std.ArrayList(RenderEntryQuadTex).init(allocator),
            .roundedFrames = std.ArrayList(RenderEntryRoundedFrame).init(allocator),
            .textLines = std.ArrayList(RenderEntryTextLine).init(allocator),
            .textBoxes = std.ArrayList(RenderEntryTextBox).init(allocator),
        };
    }

    pub fn deinit(self: Self) void
    {
        self.quads.deinit();
        self.quadTexs.deinit();
        self.roundedFrames.deinit();
        self.textLines.deinit();
        self.textBoxes.deinit();
    }

    pub fn quadGradient(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, colorTL: m.Vec4, colorTR: m.Vec4, colorBL: m.Vec4, colorBR: m.Vec4) void
    {
        (self.quads.addOne() catch return).* = RenderEntryQuad {
            .topLeft = topLeft,
            .size = size,
            .depth = depth,
            .colorTL = colorTL,
            .colorTR = colorTR,
            .colorBL = colorBL,
            .colorBR = colorBR,
        };
    }

    pub fn quad(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, color: m.Vec4) void
    {
        self.quadGradient(topLeft, size, depth, color, color, color, color);
    }

    pub fn quadTexUvOffset(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, uvOffset: m.Vec2, uvScale: m.Vec2, textureId: c_uint, color: m.Vec4) void
    {
        (self.quadTexs.addOne() catch return).* = RenderEntryQuadTex {
            .topLeft = topLeft,
            .size = size,
            .depth = depth,
            .uvOffset = uvOffset,
            .uvScale = uvScale,
            .textureId = textureId,
            .color = color,
        };
    }

    pub fn quadTex(self: *Self, topLeft: m.Vec2, size: m.Vec2, depth: f32, textureId: c_uint, color: m.Vec4) void
    {
        self.quadTexUvOffset(topLeft, size, depth, m.Vec2.zero, m.Vec2.one, textureId, color);
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

    pub fn renderShapes(self: Self, renderState: RenderState, screenSize: m.Vec2, scrollY: f32) void
    {
        for (self.quads.items) |e| {
            const posBottomLeft = posTopLeftToBottomLeft(e.topLeft, e.size, screenSize, scrollY);
            renderState.quadState.drawQuadGradient(posBottomLeft, e.size, e.depth, e.colorTL, e.colorTR, e.colorBL, e.colorBR, screenSize);
        }
        for (self.quadTexs.items) |e| {
            const posBottomLeft = posTopLeftToBottomLeft(e.topLeft, e.size, screenSize, scrollY);
            renderState.quadTexState.drawQuadUvOffset(posBottomLeft, e.size, e.depth, e.uvOffset, e.uvScale, e.textureId, e.color, screenSize);
        }
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
};
