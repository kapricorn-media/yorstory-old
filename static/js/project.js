const IMAGE_CHANGE_SPEED_MS = 300;

// let _imageElements = [];
// let _activeImageIndex = 0;

function generateEntry(entry)
{
    const landingBackground = document.getElementById("landingBackground");
    Array.from(document.getElementsByClassName("landingProjectImage")).forEach(el => {
        el.remove();
    });

    const el = document.createElement("img");
    el.classList.add("landingProjectImage");
    el.style.position = "absolute";
    el.style.width = "100%";
    // if (i !== _activeImageIndex) {
    //     el.style.visibility = "hidden";
    // }
    // el.onload = function() {
    //     const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
    //     this.style.left = px(left);
    // };
    el.src = entry.landing;
    landingBackground.appendChild(el);

    // loadImages([entry.images], function(index) {
    //     if (index !== 0) {
    //         console.error("unexpected load index " + i.toString());
    //     }
    //     console.log(index);

    //     const landingBackground = document.getElementById("landingBackground");
    //     Array.from(document.getElementsByClassName("landingProjectImage")).forEach(el => {
    //         el.remove();
    //     });
    //     for (let i = 0; i < entry.images.length; i++) {
    //         const el = document.createElement("img");
    //         el.classList.add("landingProjectImage");
    //         el.style.position = "absolute";
    //         el.style.width = "100%";
    //         if (i !== _activeImageIndex) {
    //             el.style.visibility = "hidden";
    //         }
    //         // el.onload = function() {
    //         //     const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
    //         //     this.style.left = px(left);
    //         // };
    //         el.src = entry.images[i];
    //         landingBackground.appendChild(el);
    //         _imageElements[i] = el;
    //     }

    //     setInterval(function() {
    //         let nextIndex = (_activeImageIndex + 1) % _imageElements.length;
    //         _imageElements[nextIndex].style.visibility = "visible";
    //         _imageElements[_activeImageIndex].style.visibility = "hidden";
    //         _activeImageIndex = nextIndex;
    //     }, IMAGE_CHANGE_SPEED_MS);
    // });

    const subprojectTemplate = document.getElementsByClassName("subproject")[0];

    const portfolio = document.getElementById("portfolio");
    for (let i = 0; i < entry.subprojects.length; i++) {
        const subproject = entry.subprojects[i];
        const el = subprojectTemplate.cloneNode(true);
        el.querySelector(".subprojectNumberText").innerHTML = (i + 1).toString();
        el.querySelector(".subprojectTitle").innerHTML = subproject.name;
        el.querySelector(".subprojectText").innerHTML = subproject.description;

        const grid = document.createElement("div");
        grid.classList.add("grid");
        for (let i = 0; i < subproject.images.length; i++) {
            const img = subproject.images[i];
            const gridItem = document.createElement("div");
            // gridItem.id = i.toString();
            gridItem.classList.add("gridItem");
            const gridItemBackground = document.createElement("div");
            gridItemBackground.classList.add("gridItemBackground");
            gridItemBackground.style.backgroundImage = "url('" + img + "')";
            gridItemBackground.style.backgroundPosition = "center";
            gridItemBackground.style.backgroundRepeat = "no-repeat";
            gridItemBackground.style.backgroundSize = "cover";
            gridItem.appendChild(gridItemBackground);
            grid.appendChild(gridItem);
        }

        el.appendChild(grid);
        portfolio.appendChild(el);
    }

    subprojectTemplate.remove();


    // const template = document.getElementsByClassName("gridItem")[0];
    // console.log(template);
    // const templateClone = document.getElementsByClassName("gridItem")[0].cloneNode(true);
    // console.log(templateClone);

    // Array.from(document.getElementsByClassName("gridItem")).forEach(item => {
    //     item.remove();
    // });

    // const projectGrid = document.getElementById("grid");

    // for (let i = 0; i < entry.images.length; i++) {
    //     const port = entry.images[i];
    //     const el = templateClone.cloneNode(true);
    //     el.id = i.toString();
    //     for (let j = 0; j < el.childNodes.length; j++) {
    //         const child = el.childNodes[j];
    //         if ("classList" in child) {
    //             if (child.classList.contains("gridItemBackground")) {
    //             	child.style.backgroundImage = "url('" + entry.images[i] + "')";
    //             	child.style.backgroundPosition = "center";
    //             	child.style.backgroundRepeat = "no-repeat";
    //             	child.style.backgroundSize = "cover";
    //             }
    //         }
    //     }
    //     projectGrid.appendChild(el);
    // }

    // templateClone.remove();
}
