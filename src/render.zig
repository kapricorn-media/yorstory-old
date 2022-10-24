const m = @import("math.zig");
const w = @import("wasm.zig");

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

        w.glDrawArrays(w.GL_TRIANGLES, 0, positions.len);
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
        const u_color = "u_color";
        const colorUniLoc = w.glGetUniformLocation(programId, &u_color[0], u_color.len);
        if (colorUniLoc == -1) {
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

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, texture);
        w.glUniform1i(self.samplerUniLoc, 0);

        w.glDrawArrays(w.GL_TRIANGLES, 0, positions.len);
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

// const QuadDraw = struct {
//     posNdc: m.Vec2,
//     scaleNdc: m.Vec2,
//     color: m.Vec4,
// };

// const QuadTextureDraw = struct {
//     posNdc: m.Vec2,
//     scaleNdc: m.Vec2,
//     uvOffset: m.Vec2,
//     uvScale: m.Vec2,
//     texture: c_uint,
// };

pub const RenderState = struct {
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
