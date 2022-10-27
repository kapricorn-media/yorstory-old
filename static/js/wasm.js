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
        // const tempCanvas = document.createElement("canvas");
        // tempCanvas.width = image.width;
        // tempCanvas.height = image.height;
        // const tempCtx = tempCanvas.getContext("2d");
        // tempCtx.drawImage(image, 0, 0, image.width, image.height);
        // const imgData = tempCtx.getImageData(0, 0, image.width, image.height);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, srcFormat, srcType, image);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        // if (isPowerOfTwo(image.width) && isPowerOfTwo(image.height)) {
        //     gl.generateMipmap(gl.TEXTURE_2D);
        // }

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
const glUniform1fv = function(locationId, x) {
    gl.uniform1fv(glUniformLocations[locationId], [x]);
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

    // browser / DOM functions
    clearAllText,
    addTextLine,
    addTextBox,
    setCursor,
    getUri,
    setUri,

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
    glUniform1fv,
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

function stressTestOne(textureUrl)
{
    // const CHUNK_SIZE_ISH = 512 * 1024;

    // httpGet("/webgl_png?path=" + textureUrl, function(status, data) {
    //     if (status !== 200) {
    //         console.log("webgl_png failed");
    //         return;
    //     }

    //     const metadata = JSON.parse(data);

    //     const texture = gl.createTexture();
    //     gl.bindTexture(gl.TEXTURE_2D, texture);
    //     gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    //     const level = 0;
    //     const internalFormat = gl.RGBA;
    //     const border = 0;
    //     const srcFormat = gl.RGBA;
    //     const srcType = gl.UNSIGNED_BYTE;
    //     gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, metadata.width, metadata.height, border, srcFormat, srcType);

    //     const chunkSize = Math.round(CHUNK_SIZE_ISH / metadata.width) * metadata.width;
    //     console.log(metadata);
    //     console.log(chunkSize);

    //     const n = (metadata.width * metadata.height) / chunkSize;
    //     for (let i = 0; i < n; i++) {
    //         const uri = `/webgl_png_chunk?path=${textureUrl}&chunkSize=${chunkSize}&index=${i}`;

    //         const image = new Image();
    //         image.onload = function() {
    //             // const tempCanvas = document.createElement("canvas");
    //             // tempCanvas.width = image.width;
    //             // tempCanvas.height = image.height;
    //             // const tempCtx = tempCanvas.getContext("2d");
    //             // tempCtx.drawImage(image, 0, 0, image.width, image.height);
    //             // const imgData = tempCtx.getImageData(0, 0, image.width, image.height);
    //             gl.bindTexture(gl.TEXTURE_2D, texture);
    //             gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, srcFormat, srcType, image);
    //             // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
    //             // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
    //             // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    //             // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    //             // if (isPowerOfTwo(image.width) && isPowerOfTwo(image.height)) {
    //             //     gl.generateMipmap(gl.TEXTURE_2D);
    //             // }

    //             // _wasmInstance.exports.onTextureLoaded(index, image.width, image.height);
    //         };
    //         image.src = uri;
    //         // httpGet(uri, function(status, data) {
    //         //     if (status !== 200) {
    //         //         console.log("webgl_png_tile failed");
    //         //         return;
    //         //     }

    //         //     gl.bindTexture(gl.TEXTURE_2D, texture);
    //         //     // gl.texSubImage2D();

    //         //     // console.log(data);
    //         // });
    //     }

    //     // _wasmInstance.exports.onTex();
    //     // console.log(data);
    // });

    // return;
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

    const image = new Image();
    image.onload = function() {
        // const tempCanvas = document.createElement("canvas");
        // tempCanvas.width = image.width;
        // tempCanvas.height = image.height;
        // const tempCtx = tempCanvas.getContext("2d");
        // tempCtx.drawImage(image, 0, 0, image.width, image.height);
        // const imgData = tempCtx.getImageData(0, 0, image.width, image.height);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, srcFormat, srcType, image);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        // if (isPowerOfTwo(image.width) && isPowerOfTwo(image.height)) {
        //     gl.generateMipmap(gl.TEXTURE_2D);
        // }

        // _wasmInstance.exports.onTextureLoaded(index, image.width, image.height);
    };
    image.src = textureUrl;
}

function stressTest()
{
    let images = [
        "/images/parallax/parallax4-1.bmp",
        "/images/parallax/parallax4-2.bmp",
        "/images/parallax/parallax4-3.bmp",
        "/images/parallax/parallax4-4.bmp",
        "/images/parallax/parallax4-5.bmp",
        "/images/parallax/parallax4-6.bmp",
    ];
    for (let i = 0; i < images.length; i++) {
        stressTestOne(images[i]);
    }
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

    const WASM_PAGE_SIZE = 64 * 1024;
    const memoryPages = Math.ceil(memoryBytes / WASM_PAGE_SIZE);
    // _memory = new WebAssembly.Memory({
    //     initial: memoryPages,
    //     maximum: memoryPages,
    // });
    // console.log(`Allocated ${memoryPages} wasm pages`);

    let importObject = {
        env: env,
    };
    // importObject.env.memcpy = function(){console.log("hi")};
    // importObject.env.memset = function(){console.log("hi")};

    WebAssembly.instantiateStreaming(fetch(wasmUri), importObject).then(function(obj) {
        _wasmInstance = obj.instance;
        const pages = Math.round(_wasmInstance.exports.memory.buffer.byteLength / WASM_PAGE_SIZE);
        if (pages < memoryPages) {
            _wasmInstance.exports.memory.grow(memoryPages - pages);
        }
        _wasmInstance.exports.onInit();

        // stressTest();
        // return;

        const onAnimationFrame = _wasmInstance.exports.onAnimationFrame;
        const dummyBackground = document.getElementById("dummyBackground");

        function step(timestamp) {
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
