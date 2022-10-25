function _documentOnLoad()
{
    console.log("_documentOnLoad");

    const memoryBytes = 512 * 1024;
    wasmInit("/yorstory.wasm", memoryBytes);
}

window.onresize = function() {
    console.log("window.onresize");
};

window.onload = function() {
    console.log("window.onload");
};
