const IMAGE_CHANGE_SPEED_MS = 300;

let _imageElements = [];
let _activeImageIndex = 0;

function generateProjectImages(projectImages)
{
    loadImages([projectImages], function(index) {
        if (index !== 0) {
            console.error("unexpected load index " + i.toString());
        }
        console.log(index);

        const landingBackground = document.getElementById("landingBackground");
        Array.from(document.getElementsByClassName("landingProjectImage")).forEach(el => {
            el.remove();
        });
        for (let i = 0; i < projectImages.length; i++) {
            const el = document.createElement("img");
            el.classList.add("landingProjectImage");
            el.style.position = "absolute";
            el.style.width = "100%";
            if (i !== _activeImageIndex) {
                el.style.visibility = "hidden";
            }
            // el.onload = function() {
            //     const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
            //     this.style.left = px(left);
            // };
            el.src = projectImages[i];
            landingBackground.appendChild(el);
            _imageElements[i] = el;
        }

        setInterval(function() {
            let nextIndex = (_activeImageIndex + 1) % _imageElements.length;
            _imageElements[nextIndex].style.visibility = "visible";
            _imageElements[_activeImageIndex].style.visibility = "hidden";
            _activeImageIndex = nextIndex;
        }, IMAGE_CHANGE_SPEED_MS);
    });

    const template = document.getElementsByClassName("gridItem")[0].cloneNode(true);

    Array.from(document.getElementsByClassName("gridItem")).forEach(item => {
        item.remove();
    });

    const projectGrid = document.getElementById("grid");

    for (let i = 0; i < projectImages.length; i++) {
        const port = projectImages[i];
        const el = template.cloneNode(true);
        el.id = i.toString();
        for (let j = 0; j < el.childNodes.length; j++) {
            const child = el.childNodes[j];
            if ("classList" in child) {
                if (child.classList.contains("gridItemBackground")) {
                	child.style.backgroundImage = "url('" + projectImages[i] + "')";
                	child.style.backgroundPosition = "center";
                	child.style.backgroundRepeat = "no-repeat";
                	child.style.backgroundSize = "cover";
                }
            }
        }
        projectGrid.appendChild(el);
    }

    template.remove();
}
