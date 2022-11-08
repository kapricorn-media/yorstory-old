let gl = null;
let _wasmInstance = null;
let _memory = null;
let _memoryPtr = null;
let _canvas = null;

let _currentHeight = null;
let _loadTextureJobs = [];

function queueLoadTextureJob(width, height, chunkSize, textureId, image, i, loaded) {
    _loadTextureJobs.push({
        width: width,
        height: height,
        chunkSize: chunkSize,
        textureId: textureId,
        image: image,
        i: i,
        loaded: loaded,
    });
}

function doLoadTextureJob(width, height, chunkSize, textureId, image, i, loaded) {
    const chunkSizeRows = Math.round(chunkSize / width);

    const level = 0;
    const xOffset = 0;
    const yOffset = height - chunkSizeRows * i - image.height;
    const srcFormat = gl.RGBA;
    const srcType = gl.UNSIGNED_BYTE;

    const texture = _glTextures[textureId];
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texSubImage2D(gl.TEXTURE_2D, level, xOffset, yOffset, srcFormat, srcType, image);

    loaded[i] = true;
    const allLoaded = loaded.every(function(el) { return el; });
    if (allLoaded) {
        _wasmInstance.exports.onTextureLoaded(textureId, width, height);
    }
}

function doNextLoadTextureJob() {
    const job = _loadTextureJobs.shift();
    if (!job) {
        return;
    }
    doLoadTextureJob(job.width, job.height, job.chunkSize, job.textureId, job.image, job.i, job.loaded);
}

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

function writeCharStr(ptr, len, toWrite) {
    if (toWrite.length > len) {
        return 0;
    }
    const bytes = new Uint8Array(_wasmInstance.exports.memory.buffer, ptr, len);
    for (let i = 0; i < toWrite.length; i++) {
        bytes[i] = toWrite.charCodeAt(i);
    }
    return toWrite.length;
};

function clearAllText() {
    Array.from(document.getElementsByClassName("_wasmTextOuter")).forEach(function(el) {
        el.remove();
    });
    Array.from(document.getElementsByClassName("_wasmTextBox")).forEach(function(el) {
        el.remove();
    });
}

// there is a margin on the left of text boxes for some reason - return an estimate of that "gap"
// TODO might depend on font family...
function getTextLeftGap(fontSize) {
    return fontSize * 0.08;
}

function addTextLine(
    textPtr, textLen, left, baselineFromTop, fontSize, letterSpacing,
    hexColorPtr, hexColorLen, fontFamilyPtr, fontFamilyLen) {
    const text = readCharStr(textPtr, textLen);
    const hexColor = readCharStr(hexColorPtr, hexColorLen);
    const fontFamily = readCharStr(fontFamilyPtr, fontFamilyLen);

    const outer = document.createElement("div");
    outer.classList.add("_wasmTextOuter");
    outer.style.left = px(left - getTextLeftGap(fontSize));
    outer.style.top = px(baselineFromTop - fontSize);
    outer.style.height = px(fontSize);

    const inner = document.createElement("div");
    inner.classList.add("_wasmTextInner");
    inner.style.fontFamily = fontFamily;
    inner.style.color = hexColor;
    inner.style.fontSize = px(fontSize);
    inner.style.lineHeight = px(fontSize);
    inner.style.letterSpacing = px(letterSpacing);
    inner.innerHTML = text;
    const strut = document.createElement("div");
    strut.classList.add("_wasmTextStrut");
    strut.style.height = px(fontSize);
    inner.appendChild(strut);

    outer.appendChild(inner);
    document.getElementById("dummyBackground").appendChild(outer);
}

function addTextBox(
    textPtr, textLen, left, top, width, fontSize, lineHeight, letterSpacing,
    hexColorPtr, hexColorLen, fontFamilyPtr, fontFamilyLen) {
    const text = readCharStr(textPtr, textLen);
    const hexColor = readCharStr(hexColorPtr, hexColorLen);
    const fontFamily = readCharStr(fontFamilyPtr, fontFamilyLen);

    const div = document.createElement("div");
    div.classList.add("_wasmTextBox");
    div.style.left = px(left - getTextLeftGap(fontSize));
    div.style.top = px(top);
    div.style.width = px(width);
    div.style.fontFamily = fontFamily;
    div.style.color = hexColor;
    div.style.fontSize = px(fontSize);
    div.style.lineHeight = px(lineHeight);
    div.style.letterSpacing = px(letterSpacing);
    div.innerHTML = text;
    document.getElementById("dummyBackground").appendChild(div);
}

function setCursor(cursorPtr, cursorLen) {
    const cursor = readCharStr(cursorPtr, cursorLen);
    document.body.style.cursor = cursor;
}

function getUri(outUriPtr, outUriLen) {
    return writeCharStr(outUriPtr, outUriLen, window.location.pathname);
}

function setUri(uriPtr, uriLen) {
    const uri = readCharStr(uriPtr, uriLen);
    window.location.href = uri;
}

const _glBuffers = [];
const _glFramebuffers = [];
const _glPrograms = [];
const _glShaders = [];
const _glTextures = [];
const _glUniformLocations = [];

function compileShader(sourcePtr, sourceLen, type) {
    const source = readCharStr(sourcePtr, sourceLen);
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if(!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw "Error compiling shader:" + gl.getShaderInfoLog(shader);
    }

    _glShaders.push(shader);
    return _glShaders.length - 1;
};

function linkShaderProgram(vertexShaderId, fragmentShaderId) {
    const program = gl.createProgram();
    gl.attachShader(program, _glShaders[vertexShaderId]);
    gl.attachShader(program, _glShaders[fragmentShaderId]);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        throw ("Error linking program:" + gl.getProgramInfoLog (program));
    }

    _glPrograms.push(program);
    return _glPrograms.length - 1;
};

function queueTextureLoadDirect(url, textureId, width, height)
{
    const image = new Image();
    image.onload = function() {
        if (width != image.width || height != image.height) {
            console.error("mismatched image dimensions");
        }

        const texture = _glTextures[textureId];
        gl.bindTexture(gl.TEXTURE_2D, texture);
        const level = 0;
        const xOffset = 0;
        const yOffset = 0;
        const srcFormat = gl.RGBA;
        const srcType = gl.UNSIGNED_BYTE;
        gl.texSubImage2D(gl.TEXTURE_2D, level, xOffset, yOffset, srcFormat, srcType, image);

        _wasmInstance.exports.onTextureLoaded(textureId, width, height);
    };
    image.src = url;
}

function queueTextureLoadChunked(url, textureId, width, height, chunkSize)
{
    if (chunkSize % width !== 0) {
        console.error("chunk size is not a multiple of image width");
        return;
    }

    const n = Math.ceil((width * height) / chunkSize);
    const loaded = new Array(n).fill(false);

    for (let i = 0; i < n; i++) {
        const uri = `/webgl_png_chunk?path=${url}&index=${i}`;

        const image = new Image();
        image.onload = function() {
            queueLoadTextureJob(width, height, chunkSize, textureId, image, i, loaded);
        };
        image.src = uri;
    }
}

function createTexture(width, height, wrap, filter) {
    const textureId = env.glCreateTexture();
    const texture = _glTextures[textureId];
    gl.bindTexture(gl.TEXTURE_2D, texture);

    const level = 0;
    const internalFormat = gl.RGBA;
    const border = 0;
    const srcFormat = gl.RGBA;
    const srcType = gl.UNSIGNED_BYTE;
    const pixels = new Uint8Array(width * height * 4);
    gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border, srcFormat, srcType, pixels);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);

    return textureId;
}

function loadTexture(textureId, imgUrlPtr, imgUrlLen, wrap, filter) {
    const imgUrl = readCharStr(imgUrlPtr, imgUrlLen);
    const chunkSizeMax = 512 * 1024;

    const texture = _glTextures[textureId];
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    const uri = `/webgl_png?path=${imgUrl}&chunkSizeMax=${chunkSizeMax}`;
    httpGet(uri, function(status, data) {
        if (status !== 200) {
            console.log("webgl_png failed");
            return;
        }

        const metadata = JSON.parse(data);
        const width = metadata.width;
        const height = metadata.height;
        const chunkSize = metadata.chunkSize;
        const level = 0;
        const internalFormat = gl.RGBA;
        const border = 0;
        const srcFormat = gl.RGBA;
        const srcType = gl.UNSIGNED_BYTE;

        const pixels = new Uint8Array(width * height * 4);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border, srcFormat, srcType, pixels);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);

        if (chunkSize === 0) {
            queueTextureLoadDirect(imgUrl, textureId, width, height);
        } else {
            queueTextureLoadChunked(imgUrl, textureId, width, height, chunkSize);
        }
    });
};

function createAndLoadTexture(imgUrlPtr, imgUrlLen, wrap, filter) {
    const imgUrl = readCharStr(imgUrlPtr, imgUrlLen);
    const chunkSizeMax = 512 * 1024;

    const textureId = env.glCreateTexture();
    const texture = _glTextures[textureId];
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    const level = 0;
    const internalFormat = gl.RGBA;
    const tempWidth = 1;
    const tempHeight = 1;
    const border = 0;
    const srcFormat = gl.RGBA;
    const srcType = gl.UNSIGNED_BYTE;
    const tempPixels = new Uint8Array([255, 255, 255, 255]);
    gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, tempWidth, tempHeight, border, srcFormat, srcType, tempPixels);

    const uri = `/webgl_png?path=${imgUrl}&chunkSizeMax=${chunkSizeMax}`;
    httpGet(uri, function(status, data) {
        if (status !== 200) {
            console.log("webgl_png failed");
            return;
        }

        const metadata = JSON.parse(data);
        const width = metadata.width;
        const height = metadata.height;
        const chunkSize = metadata.chunkSize;

        const pixels = new Uint8Array(width * height * 4);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border, srcFormat, srcType, pixels);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);

        if (chunkSize === 0) {
            queueTextureLoadDirect(imgUrl, textureId, width, height);
        } else {
            queueTextureLoadChunked(imgUrl, textureId, width, height, chunkSize);
        }
    });

    return textureId;
};

function bindNullFramebuffer() {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
}

const env = {
    // Debug functions
    consoleMessage,

    // browser / DOM functions
    clearAllText,
    addTextLine,
    addTextBox,
    setCursor,
    getUri,
    setUri,

    // GL derived functions
    compileShader,
    linkShaderProgram,
    createAndLoadTexture,
    createTexture,
    loadTexture,
    bindNullFramebuffer
};

function fillGlFunctions(env)
{
    if (gl === null) {
        console.error("gl is null");
        return;
    }

    for (let k in gl) {
        const type = typeof gl[k];
        if (type === "function") {
            const prefixed = "gl" + k[0].toUpperCase() + k.substring(1);
            env[prefixed] = function() {
                return gl[k].apply(gl, arguments);
            };
        }
    }

    env.glCreateBuffer = function() {
        _glBuffers.push(gl.createBuffer());
        return _glBuffers.length - 1;
    };
    env.glBindBuffer = function(type, bufferId) {
        gl.bindBuffer(type, _glBuffers[bufferId]);
    };
    env.glBufferData = function(type, dataPtr, count, drawType) {
        const floats = new Float32Array(_wasmInstance.exports.memory.buffer, dataPtr, count);
        gl.bufferData(type, floats, drawType);
    };

    env.glCreateFramebuffer = function() {
        _glFramebuffers.push(gl.createFramebuffer());
        return _glFramebuffers.length - 1;
    };
    env.glBindFramebuffer = function(framebufferType, framebufferId) {
        gl.bindFramebuffer(framebufferType, _glFramebuffers[framebufferId]);
    };
    env.glFramebufferTexture2D = function(framebufferType, attachmentPoint, textureType, textureId, level) {
        gl.framebufferTexture2D(framebufferType, attachmentPoint, textureType, _glTextures[textureId], level);
    };

    env.glCreateTexture = function() {
        _glTextures.push(gl.createTexture());
        return _glTextures.length - 1;
    };
    env.glBindTexture = function(textureType, textureId) {
        gl.bindTexture(textureType, _glTextures[textureId]);
    };

    env.glUseProgram = function(programId) {
        gl.useProgram(_glPrograms[programId]);
    };
    env.glGetAttribLocation = function(programId, namePtr, nameLen) {
        const name = readCharStr(namePtr, nameLen);
        return  gl.getAttribLocation(_glPrograms[programId], name);
    };
    env.glGetUniformLocation = function(programId, namePtr, nameLen)  {
        const name = readCharStr(namePtr, nameLen);
        const uniformLocation = gl.getUniformLocation(_glPrograms[programId], name);
        _glUniformLocations.push(uniformLocation);
        return _glUniformLocations.length - 1;
    };
    env.glUniform1i = function(locationId, value) {
        gl.uniform1i(_glUniformLocations[locationId], value);
    };
    env.glUniform1fv = function(locationId, x) {
        gl.uniform1fv(_glUniformLocations[locationId], [x]);
    };
    env.glUniform2fv = function(locationId, x, y) {
        gl.uniform2fv(_glUniformLocations[locationId], [x, y]);
    };
    env.glUniform3fv = function(locationId, x, y, z) {
        gl.uniform3fv(_glUniformLocations[locationId], [x, y, z]);
    };
    env.glUniform4fv = function(locationId, x, y, z, w) {
        gl.uniform4fv(_glUniformLocations[locationId], [x, y, z, w]);
    };
}

function updateCanvasSize()
{
    _canvas.width = window.innerWidth;
    _canvas.height = window.innerHeight;

    gl.viewport(0, 0, _canvas.width, _canvas.height);

    console.log(`canvas resize: ${_canvas.width} x ${_canvas.height}`);
}

function wasmInit(wasmUri, memoryBytes)
{
    _canvas = document.getElementById("canvas");
    gl = _canvas.getContext("webgl") || _canvas.getContext("experimental-webgl");
    updateCanvasSize();

    document.addEventListener("mousemove", function(event) {
        if (_wasmInstance !== null) {
            _wasmInstance.exports.onMouseMove(event.clientX, event.clientY);
        }
    });
    document.addEventListener("mousedown", function(event) {
        if (_wasmInstance !== null) {
            _wasmInstance.exports.onMouseDown(event.button, event.clientX, event.clientY);
        }
    });
    document.addEventListener("mouseup", function(event) {
        if (_wasmInstance !== null) {
            _wasmInstance.exports.onMouseUp(event.button, event.clientX, event.clientY);
        }
    });
    document.addEventListener("keydown", function(event) {
        if (_wasmInstance !== null) {
            _wasmInstance.exports.onKeyDown(event.keyCode);
        }
    });

    addEventListener("resize", function() {
        updateCanvasSize();
    });

    // const WASM_PAGE_SIZE = 64 * 1024;
    // const memoryPages = Math.ceil(memoryBytes / WASM_PAGE_SIZE);
    // _memory = new WebAssembly.Memory({
    //     initial: memoryPages,
    //     maximum: memoryPages,
    // });
    // console.log(`Allocated ${memoryPages} wasm pages`);

    let importObject = {
        env: env,
    };
    fillGlFunctions(importObject.env, gl);

    WebAssembly.instantiateStreaming(fetch(wasmUri), importObject).then(function(obj) {
        _wasmInstance = obj.instance;
        // const pages = Math.round(_wasmInstance.exports.memory.buffer.byteLength / WASM_PAGE_SIZE);
        // if (pages < memoryPages) {
        //     _wasmInstance.exports.memory.grow(memoryPages - pages);
        // }
        _wasmInstance.exports.onInit();

        const onAnimationFrame = _wasmInstance.exports.onAnimationFrame;
        const dummyBackground = document.getElementById("dummyBackground");

        function step(timestamp) {
            doNextLoadTextureJob();

            const scrollY = document.documentElement.scrollTop || document.body.scrollTop;
            const totalHeight = onAnimationFrame(_canvas.width, _canvas.height, scrollY, timestamp);
            if (totalHeight !== 0 && _currentHeight !== totalHeight) {
                _currentHeight = totalHeight;
                dummyBackground.style.height = px(totalHeight);
            }
            window.requestAnimationFrame(step);
        }
        window.requestAnimationFrame(step);
    });
}
