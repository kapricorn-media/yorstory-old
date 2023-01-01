let gl = null;
let _wasmInstance = null;
let _memory = null;
let _memoryPtr = null;
let _canvas = null;

let _currentHeight = null;
let _loadTextureJobs = [];

function createLoadTextureJob(width, height, chunkSize, textureId, pngData, i, loaded) {
    return {
        width: width,
        height: height,
        chunkSize: chunkSize,
        textureId: textureId,
        pngData: pngData,
        i: i,
        loaded: loaded,
    };
}

function queueLoadTextureJob(width, height, chunkSize, textureId, pngData, i, loaded) {
    _loadTextureJobs.push(createLoadTextureJob(width, height, chunkSize, textureId, pngData, i, loaded));
}

function doLoadTextureJob(job) {
    const image = new Image();
    image.onload = function() {
        const chunkSizeRows = Math.round(job.chunkSize / job.width);

        const level = 0;
        const xOffset = 0;
        const yOffset = job.height - chunkSizeRows * job.i - image.height;
        const srcFormat = gl.RGBA;
        const srcType = gl.UNSIGNED_BYTE;

        const texture = _glTextures[job.textureId];
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texSubImage2D(gl.TEXTURE_2D, level, xOffset, yOffset, srcFormat, srcType, image);

        job.loaded[job.i] = true;
        const allLoaded = job.loaded.every(function(el) { return el; });
        if (allLoaded) {
            _wasmInstance.exports.onTextureLoaded(job.textureId, job.width, job.height);
        }
    };
    uint8ArrayToImageSrcAsync(job.pngData, function(src) {
        image.src = src;
    });
}

function doNextLoadTextureJob() {
    const job = _loadTextureJobs.shift();
    if (!job) {
        return;
    }
    doLoadTextureJob(job);
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
    Array.from(document.getElementsByClassName("_wasmTextAll")).forEach(function(el) {
        el.remove();
    });
}

function setAllTextOpacity(opacity) {
    Array.from(document.getElementsByClassName("_wasmTextAll")).forEach(function(el) {
        el.style.opacity = opacity;
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
    outer.classList.add("_wasmTextAll");
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
    hexColorPtr, hexColorLen, fontFamilyPtr, fontFamilyLen, textAlignPtr, textAlignLen) {
    const text = readCharStr(textPtr, textLen);
    const hexColor = readCharStr(hexColorPtr, hexColorLen);
    const fontFamily = readCharStr(fontFamilyPtr, fontFamilyLen);
    const textAlign = readCharStr(textAlignPtr, textAlignLen);

    const div = document.createElement("div");
    div.classList.add("_wasmTextAll");
    div.classList.add("_wasmTextBox");
    div.style.left = px(left - getTextLeftGap(fontSize));
    div.style.top = px(top);
    div.style.width = px(width);
    div.style.fontFamily = fontFamily;
    div.style.color = hexColor;
    div.style.fontSize = px(fontSize);
    div.style.lineHeight = px(lineHeight);
    div.style.letterSpacing = px(letterSpacing);
    div.style.textAlign = textAlign;
    div.innerHTML = text;
    document.getElementById("dummyBackground").appendChild(div);
}

function clearAllEmbeds()
{
    Array.from(document.getElementsByClassName("_wasmEmbedAll")).forEach(function(el) {
        el.remove();
    });
}

function addYoutubeEmbed(left, top, width, height, youtubeIdPtr, youtubeIdLen)
{
    const youtubeId = readCharStr(youtubeIdPtr, youtubeIdLen);

    const div = document.createElement("div");
    div.classList.add("_wasmTextAll");
    div.classList.add("_wasmYoutubeEmbed");
    div.style.left = px(left);
    div.style.top = px(top);
    div.style.width = px(width);
    div.style.height = px(height);

    const iframe = document.createElement("iframe");
    iframe.style.width = "100%";
    iframe.style.height = "100%";
    iframe.src = "https://www.youtube.com/embed/" + youtubeId;
    iframe.title = "YouTube video player";
    iframe.frameborder = "0";
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture";
    iframe.allowFullscreen = true;

    div.appendChild(iframe);
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
const _glRenderbuffers = [];
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

function initBufferIt(buffer)
{
    return {
        index: 0,
        array: new Uint8Array(buffer),
    };
}

function readBigEndianU64(bufferIt)
{
    if (bufferIt.index + 8 > bufferIt.array.length) {
        throw "BE U64 out of bounds";
    }
    let value = 0;
    for (let i = 0; i < 8; i++) {
        value += bufferIt.array[bufferIt.index + i] * (1 << ((7 - i) * 8));
    }
    bufferIt.index += 8;
    return value;
}

function loadTexture(textureId, imgUrlPtr, imgUrlLen, wrap, filter) {
    const imgUrl = readCharStr(imgUrlPtr, imgUrlLen);
    const chunkSizeMax = 512 * 1024;

    const texture = _glTextures[textureId];
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    const uri = `/webgl_png?path=${imgUrl}`;
    httpGet(uri, function(status, data) {
        if (status !== 200) {
            console.log(`webgl_png failed with status ${status} for URL ${imgUrl}`);
            _wasmInstance.exports.onTextureLoaded(textureId, 0, 0);
            return;
        }

        const it = initBufferIt(data);
        const width = readBigEndianU64(it);
        const height = readBigEndianU64(it);
        const chunkSize = readBigEndianU64(it);
        const numChunks = readBigEndianU64(it);

        if (chunkSize % width !== 0) {
            console.error("chunk size is not a multiple of image width");
            return;
        }

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

        const loaded = new Array(numChunks).fill(false);
        for (let i = 0; i < numChunks; i++) {
            const chunkLen = readBigEndianU64(it);
            const chunkData = it.array.subarray(it.index, it.index + chunkLen);
            it.index += chunkLen;
            queueLoadTextureJob(width, height, chunkSize, textureId, chunkData, i, loaded);
        }
    });
};

function bindNullFramebuffer() {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
}

const env = {
    // Debug functions
    consoleMessage,

    // browser / DOM functions
    clearAllText,
    setAllTextOpacity,
    addTextLine,
    addTextBox,
    clearAllEmbeds,
    addYoutubeEmbed,
    setCursor,
    getUri,
    setUri,

    // GL derived functions
    compileShader,
    linkShaderProgram,
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
    env.glBindBuffer = function(type, id) {
        gl.bindBuffer(type, _glBuffers[id]);
    };
    env.glBufferData = function(type, dataPtr, count, drawType) {
        const floats = new Float32Array(_wasmInstance.exports.memory.buffer, dataPtr, count);
        gl.bufferData(type, floats, drawType);
    };

    env.glCreateFramebuffer = function() {
        _glFramebuffers.push(gl.createFramebuffer());
        return _glFramebuffers.length - 1;
    };
    env.glBindFramebuffer = function(type, id) {
        gl.bindFramebuffer(type, _glFramebuffers[id]);
    };
    env.glFramebufferTexture2D = function(type, attachment, textureType, textureId, level) {
        gl.framebufferTexture2D(type, attachment, textureType, _glTextures[textureId], level);
    };
    env.glFramebufferRenderbuffer = function(type, attachment, renderbufferTarget, renderbufferId) {
        gl.framebufferRenderbuffer(type, attachment, renderbufferTarget, _glRenderbuffers[renderbufferId]);
    };

    env.glCreateRenderbuffer = function() {
        _glRenderbuffers.push(gl.createRenderbuffer());
        return _glRenderbuffers.length - 1;
    };
    env.glBindRenderbuffer = function(type, id) {
        gl.bindRenderbuffer(type, _glRenderbuffers[id]);
    };

    env.glCreateTexture = function() {
        _glTextures.push(gl.createTexture());
        return _glTextures.length - 1;
    };
    env.glBindTexture = function(type, id) {
        gl.bindTexture(type, _glTextures[id]);
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
    // _canvas.width = window.screen.width;
    // _canvas.height = window.screen.height;

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
            doNextLoadTextureJob(); // TODO make fancier?

            const scrollY = window.scrollY;
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
