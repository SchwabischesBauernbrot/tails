document.addEventListener("DOMContentLoaded", function() {

  /* Toggle warnings */

  let warnings = ["identity", "tor", "computer"];

  function hideAllWarnings(evt) {
    warnings.forEach(function(element) {
      document.getElementById("detailed-" + element).style.display = "none";
      document.getElementById("toggle-" + element).classList.remove("button-revealed");
    });

  }

  function toggleWarnings(warning, evt) {
    let elem = document.getElementById("detailed-" + warning);
    let style = elem.style;
    if (style.display == "block") {
      hideAllWarnings(evt);
      return
    } else {
      hideAllWarnings(evt);
      style.display = "block";
      let btn = document.getElementById("toggle-" + warning);
      btn.classList.add("button-revealed")
    }
  }

  warnings.forEach(warning => {
    let toggle = document.getElementById("toggle-" + warning);
    if(toggle) {
      toggle.onclick = function(e) { toggleWarnings(warning, e); }
    }
    let hide = document.getElementById("hide-" + warning);
    if(hide) {
      hide.onclick = function(e) { hideAllWarnings(e); }
    }
  });

  /* Change PNG images of class 'svg' to SVG images (#17805) */

  var svgs = document.getElementsByClassName("svg");
  for (let i = 0; i < svgs.length; i++) {
    svgs[i].src = svgs[i].src.replace(/\.png$/, '.svg');
  }

});
