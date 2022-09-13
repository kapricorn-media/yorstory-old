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
