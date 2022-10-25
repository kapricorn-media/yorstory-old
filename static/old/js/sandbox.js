function _documentOnLoad()
{
    console.log("_documentOnLoad");

    wasmInit();
}

window.onresize = function() {
    console.log("window.onresize");
};

window.onload = function() {
    console.log("window.onload");
};
