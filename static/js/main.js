let _memory;
let _canvas = null;
let gl = null;

function consoleLog(messagePtr, messageLen) {
    const message = readCharStr(messagePtr, messageLen);
    console.log(message);
}

function isPowerOfTwo(x) {
    return (Math.log(x)/Math.log(2)) % 1 === 0;
}

const readCharStr = function(ptr, len) {
    const bytes = new Uint8Array(_memory.buffer, ptr, len);
    return new TextDecoder("utf-8").decode(bytes);
};

const glShaders = [];
const glPrograms = [];
const glBuffers = [];
const glUniformLocations = [];
const glTextures = [];

const compileShader = function(sourcePtr, sourceLen, type) {
    const source = readCharStr(sourcePtr, sourceLen);
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if(!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw "Error compiling shader:" + gl.getShaderInfoLog(shader);
    }

    glShaders.push(shader);
    return glShaders.length - 1;
};

const linkShaderProgram = function(vertexShaderId, fragmentShaderId) {
    const program = gl.createProgram();
    gl.attachShader(program, glShaders[vertexShaderId]);
    gl.attachShader(program, glShaders[fragmentShaderId]);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        throw ("Error linking program:" + gl.getProgramInfoLog (program));
    }
    glPrograms.push(program);
    return glPrograms.length - 1;
};

const createTexture = function(imgUrlPtr, imgUrlLen) {
    const imgUrl = readCharStr(imgUrlPtr, imgUrlLen);

    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    const level = 0;
    const internalFormat = gl.RGBA;
    const width = 1;
    const height = 1;
    const border = 0;
    const srcFormat = gl.RGBA;
    const srcType = gl.UNSIGNED_BYTE;
    const pixel = new Uint8Array([0, 0, 255, 255]);  // opaque blue
    gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border, srcFormat, srcType, pixel);

    const image = new Image();
    image.onload = function() {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, srcFormat, srcType, image);

        // WebGL1 has different requirements for power of 2 images
        // vs non power of 2 images so check if the image is a
        // power of 2 in both dimensions.
        if (isPowerOfTwo(image.width) && isPowerOfTwo(image.height)) {
            // Yes, it's a power of 2. Generate mips.
            gl.generateMipmap(gl.TEXTURE_2D);
        } else {
            // No, it's not a power of 2. Turn off mips and set
            // wrapping to clamp to edge
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        }
    };
    image.src = imgUrl;

    glTextures.push(texture);
    return glTextures.length - 1;
};

const glClearColor = function(r, g, b, a) {
    gl.clearColor(r, g, b, a);
};
const glEnable = function(x) {
    gl.enable(x);
};
const glDepthFunc = function(x) {
    gl.depthFunc(x);
};
const glClear = function(x) {
    gl.clear(x);
};

const glGetAttribLocation = function(programId, namePtr, nameLen) {
    const name = readCharStr(namePtr, nameLen);
    return  gl.getAttribLocation(glPrograms[programId], name);
};
const glGetUniformLocation = function(programId, namePtr, nameLen)  {
    glUniformLocations.push(gl.getUniformLocation(glPrograms[programId], readCharStr(namePtr, nameLen)));
    return glUniformLocations.length - 1;
};

const glUniform1i = function(locationId, value) {
    gl.uniform1i(glUniformLocations[locationId], value);
};
const glUniform2fv = function(locationId, x, y) {
    gl.uniform2fv(glUniformLocations[locationId], [x, y]);
};
const glUniform3fv = function(locationId, x, y, z) {
    gl.uniform3fv(glUniformLocations[locationId], [x, y, z]);
};
const glUniform4fv = function(locationId, x, y, z, w) {
    gl.uniform4fv(glUniformLocations[locationId], [x, y, z, w]);
};

const glCreateBuffer = function() {
    glBuffers.push(gl.createBuffer());
    return glBuffers.length - 1;
};
const glBindBuffer = function(type, bufferId) {
    gl.bindBuffer(type, glBuffers[bufferId]);
};
const glBufferData = function(type, dataPtr, count, drawType) {
    const floats = new Float32Array(_memory.buffer, dataPtr, count);
    gl.bufferData(type, floats, drawType);
};

const glUseProgram = function(programId) {
    gl.useProgram(glPrograms[programId]);
};

const glEnableVertexAttribArray = function(x) {
    gl.enableVertexAttribArray(x);
};
const glVertexAttribPointer = function(attribLocation, size, type, normalize, stride, offset) {
    gl.vertexAttribPointer(attribLocation, size, type, normalize, stride, offset);
};

const glActiveTexture = function(texture) {
    gl.activeTexture(texture);
};
const glBindTexture = function(textureType, textureId) {
    gl.bindTexture(textureType, glTextures[textureId]);
};

const glDrawArrays = function(type, offset, count) {
    gl.drawArrays(type, offset, count);
};

const env = {
    consoleLog,
    compileShader,
    linkShaderProgram,
    createTexture,

    glClearColor,
    glEnable,
    glDepthFunc,
    glClear,

    glGetAttribLocation,
    glGetUniformLocation,

    glUniform1i,
    glUniform2fv,
    glUniform3fv,
    glUniform4fv,

    glCreateBuffer,
    glBindBuffer,
    glBufferData,

    glUseProgram,

    glEnableVertexAttribArray,
    glVertexAttribPointer,

    glActiveTexture,
    glBindTexture,

    glDrawArrays,
};

function fetchAndInstantiate(url, importObject) {
    return fetch(url).then(function(response) {
        return response.arrayBuffer();
    }).then(function(bytes) {
        return WebAssembly.instantiate(bytes, importObject);
    }).then(function(results) {
        return results.instance;
    });
}

window.onload = function() {
    console.log("window.onload");

    _canvas = document.getElementById("canvas");
    _canvas.width = window.innerWidth;
    _canvas.height = window.innerHeight;
    console.log(`canvas: ${_canvas.width} x ${_canvas.height}`);

    gl = _canvas.getContext('webgl') || _canvas.getContext('experimental-webgl');
    gl.viewport(0, 0, _canvas.width, _canvas.height);

    fetchAndInstantiate("yorstory.wasm", {env}).then(function(instance) {
        _memory = instance.exports.memory;
        instance.exports.onInit();

        const onAnimationFrame = instance.exports.onAnimationFrame;

        function step(timestamp) {
            onAnimationFrame(_canvas.width, _canvas.height, timestamp);
            window.requestAnimationFrame(step);
        }
        window.requestAnimationFrame(step);
    });
};