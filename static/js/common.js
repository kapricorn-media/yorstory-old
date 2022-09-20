function px(n)
{
    return n.toString() + "px";
}

function httpGet(url, callback)
{
    const request = new XMLHttpRequest();
    request.open("GET", url);
    request.responseType = "text";
    request.send();
    request.onreadystatechange = function() {
        if (this.readyState == 4) {
            const responseOk = this.status === 200;
            callback(this.status, responseOk ? request.responseText : null);
        }
    };
}

function httpPost(url, data, callback)
{
    const request = new XMLHttpRequest();
    request.open("POST", url);
    request.responseType = "text";
    request.send(data);
    request.onreadystatechange = function() {
        if (this.readyState == 4) {
            const responseOk = this.status === 200;
            callback(this.status, responseOk ? request.responseText : null);
        }
    };
}

let _loadedImages = {};

// Takes an array of arrays of images to load, in sequence
function loadImages(imageSequence, callbackComplete)
{
    let sequenceLoaded = [];
    for (let i = 0; i < imageSequence.length; i++) {
        sequenceLoaded.push(false);
    }

    for (let i = 0; i < imageSequence.length; i++) {
        if (sequenceLoaded[i]) {
            continue;
        }

        let loaded = false;
        if (imageSequence[i][0] in _loadedImages) {
            loaded = true;
            for (let j = 0; j < imageSequence[i].length; j++) {
                const imgSrc = imageSequence[i][j];
                if (!_loadedImages[imgSrc].complete) {
                    loaded = false;
                    break;
                }
            }
        } else {
            for (let j = 0; j < imageSequence[i].length; j++) {
                const imgSrc = imageSequence[i][j];
                _loadedImages[imgSrc] = new Image();
                _loadedImages[imgSrc].onload = function() {
                    loadImages(imageSequence, callbackComplete);
                };
                _loadedImages[imgSrc].src = imgSrc;
            }
        }

        if (loaded) {
            sequenceLoaded[i] = true;
            callbackComplete(i);
        } else {
            break;
        }
    }
}
