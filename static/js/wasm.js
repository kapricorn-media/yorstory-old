let _wasmInstance = null;
let _memory = null;
let _canvas = null;
let gl = null;

let _currentHeight = null;

function consoleMessage(isError, messagePtr, messageLen) {
    const message = readCharStr(messagePtr, messageLen);
    if (isError) {
        console.error(message);
    } else {
        console.log(message);
    }
}

function isPowerOfTwo(x) {
    return (Math.log(x)/Math.log(2)) % 1 === 0;
}

function readCharStr(ptr, len) {
    const bytes = new Uint8Array(_wasmInstance.exports.memory.buffer, ptr, len);
    return new TextDecoder("utf-8").decode(bytes);
};

function clearAllText() {
    Array.from(document.getElementsByClassName("_wasmText")).forEach(function(el) {
        el.remove();
    });
}

function addText(textPtr, textLen, left, top, fontSize) {
    const text = readCharStr(textPtr, textLen);

    const div = document.createElement("div");
    div.classList.add("_wasmText");
    div.style.position = "absolute";
    div.style.top = px(top - fontSize);
    div.style.left = px(left);
    const span = document.createElement("span");
    span.innerHTML = text;
    span.style.fontSize = px(fontSize);
    span.style.verticalAlign = "baseline";
    div.appendChild(span);
    document.getElementById("dummyBackground").appendChild(div);
}

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

const createTexture = function(imgUrlPtr, imgUrlLen, wrap) {
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
    const pixel = new Uint8Array([255, 255, 255, 255]);
    gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border, srcFormat, srcType, pixel);

    glTextures.push(texture);
    const index = glTextures.length - 1;

    const image = new Image();
    image.onload = function() {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, srcFormat, srcType, image);

        if (isPowerOfTwo(image.width) && isPowerOfTwo(image.height)) {
            gl.generateMipmap(gl.TEXTURE_2D);
        } else {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        }

        _wasmInstance.exports.onTextureLoaded(index, image.width, image.height);
    };
    image.src = imgUrl;

    return index;
};

const glClear = function(x) {
    gl.clear(x);
};
const glClearColor = function(r, g, b, a) {
    gl.clearColor(r, g, b, a);
};

const glEnable = function(x) {
    gl.enable(x);
};

const glBlendFunc = function(x, y) {
    gl.blendFunc(x, y);
};
const glDepthFunc = function(x) {
    gl.depthFunc(x);
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
    const floats = new Float32Array(_wasmInstance.exports.memory.buffer, dataPtr, count);
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
    // Debug functions
    consoleMessage,

    // DOM functions
    clearAllText,
    addText,

    // GL functions
    compileShader,
    linkShaderProgram,
    createTexture,

    glClear,
    glClearColor,

    glEnable,

    glBlendFunc,
    glDepthFunc,

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

function updateCanvasSize()
{
    _canvas.width = window.innerWidth;
    _canvas.height = window.innerHeight;

    gl.viewport(0, 0, _canvas.width, _canvas.height);

    console.log(`canvas resize: ${_canvas.width} x ${_canvas.height}`);
}

function wasmInit()
{
    _canvas = document.getElementById("canvas");
    gl = _canvas.getContext("webgl") || _canvas.getContext("experimental-webgl");
    updateCanvasSize();

    _canvas.addEventListener("click", function(event) {
        if (_wasmInstance !== null) {
            _wasmInstance.exports.onClick(event.clientX, window.innerHeight - event.clientY);
        }
    });

    addEventListener("resize", function() {
        updateCanvasSize();
    });

    const WASM_PAGE_SIZE = 64 * 1024;
    const memoryBytes = 4 * 1024 * 1024;
    const memoryPages = Math.ceil(memoryBytes / WASM_PAGE_SIZE);
    _memory = new WebAssembly.Memory({
        initial: memoryPages,
        maximum: memoryPages,
    });
    console.log(`Allocated ${memoryPages} wasm pages`);

    let importObject = {
        env: env,
    };
    console.log(importObject);

    WebAssembly.instantiateStreaming(fetch("yorstory.wasm"), importObject).then(function(obj) {
        _wasmInstance = obj.instance;
        obj.instance.exports.onInit(_memory.buffer);

        const onAnimationFrame = obj.instance.exports.onAnimationFrame;
        const dummyBackground = document.getElementById("dummyBackground");

        function step(timestamp) {
            const scrollY = document.documentElement.scrollTop || document.body.scrollTop;
            const totalHeight = onAnimationFrame(_canvas.width, _canvas.height, scrollY, timestamp);
            if (_currentHeight !== totalHeight) {
                _currentHeight = totalHeight;
                dummyBackground.style.height = px(totalHeight);
            }
            window.requestAnimationFrame(step);
        }
        window.requestAnimationFrame(step);
    });
}
