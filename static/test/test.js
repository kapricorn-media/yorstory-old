function _documentOnLoad()
{
    httpGet("/png_test", function(status, data) {
        if (status !== 200) {
            console.error(status);
            return;
        }

        const theImage = document.getElementById("theImage");
        theImage.src = arrayBufferToImageSrc(data);
    });
}

window.onresize = function() {
    console.log("window.onresize");
};

window.onload = function() {
    console.log("window.onload");
};
