document.addEventListener("DOMContentLoaded", function() {

  window.addEventListener("message", receiveMessage);

  function receiveMessage(event) {
    if (event.source !== window || event.origin !== "https://tails.boum.org" || !event.data) {
      return;
    }
    if (event.data.action === "verifying") {
      showVerifyingDownload(event.data.fileName);
    }
    else if (event.data.action === "verification-failed") {
      showVerificationResult("failed");
    }
    else if (event.data.action === "verification-failed-again") {
      showVerificationResult("failed-again");
    }
    else if (event.data.action === "verification-success") {
      showVerificationResult("successful");
    }
    else if (event.data.action === "progress") {
      showVerificationProgress(event.data.percentage);
    }
    else if (event.data.action === "extension-installed") {
      if (document.documentElement.dataset.extension === "up-to-date") {
        showVerifyDownload();
      }
      else if (document.documentElement.dataset.extension === "outdated") {
        showUpdateExtension();
      }
    }
  }

  // Display floating-toggleable-links to prevent people without JS to
  // either always see the toggles or have broken toggle links.
  function showFloatingToggleableLinks() {
    var links = document.getElementsByClassName("floating-toggleable-link");
    for (let i = 0; i < links.length; i++) {
      show(links[i]);
    }
  }
  showFloatingToggleableLinks();

  function opaque(elm) {
    elm.classList.remove('transparent');
    var siblings = elm.querySelectorAll("a");
    for (let i = 0; i < siblings.length; i++) {
      siblings[i].style.pointerEvents = "auto";
    }
  }

  function transparent(elm) {
    elm.classList.add('transparent');
    var siblings = elm.querySelectorAll("a");
    for (let i = 0; i < siblings.length; i++) {
      siblings[i].style.pointerEvents = "none";
    }
  }

  function toggleOpacity(elm, mode) {
    for (let i = 0; i < elm.length; i++) {
      if (mode == "opaque") {
        opaque(elm[i]);
      } else {
        transparent(elm[i]);
      }
    }
  }

  function hide(elm) {
    elm.style.display = "none";
  }

  function show(elm) {
    elm.style.display = "initial";
    if (elm.classList.contains("block")) {
      elm.style.display = "block";
    }
    if (elm.classList.contains("inline-block")) {
      elm.style.display = "inline-block";
    }
  }

  function toggleDisplay(elm, mode) {
    for (let i = 0; i < elm.length; i++) {
      if (mode == "hide") {
        hide(elm[i]);
      } else {
        show(elm[i]);
      }
    }
  }

  function detectBrowser() {
    /* To list the APIs that our extension is using, execute: git grep "chrome."
       Browser compatibility:

         - https://developer.mozilla.org/en-US/Add-ons/WebExtensions/Browser_support_for_JavaScript_APIs
         - https://developer.chrome.com/extensions/api_index
    */
    minVersion = {
      "firefox": 52,  // Tor Browser when releasing Tails Verification 1.0
      "chrome": 57,   // Version from Debian Jessie, the oldest I could test
      "torbrowser": 7 // First release based on Firefox 52
    };
    document.getElementById("min-version-firefox").textContent = minVersion.firefox.toString();
    document.getElementById("min-version-chrome").textContent = minVersion.chrome.toString();
    document.getElementById("min-version-tor-browser").textContent = minVersion.torbrowser.toString();

    version = navigator.userAgent.match(/\b(Chrome|Firefox)\/(\d+)/);
    version = version && parseInt(version[2]) || 0;
    overrideVersion = location.search.match(/\bversion=(\w+)/);
    if (overrideVersion) {
      version = overrideVersion[1];
    }

    overrideBrowser = location.search.match(/\bbrowser=(\w+)/);
    if (overrideBrowser) {
      browser = overrideBrowser[1];
    } else if (window.InstallTrigger) {
      browser = "Firefox";
    } else if ((/\bChrom/).test(navigator.userAgent) && (/\bGoogle Inc\./).test(navigator.vendor)) {
      browser = "Chrome";
    }

    if (browser === "Firefox" || browser === "Chrome") {
      document.getElementById("detected-browser").textContent = browser + " " + version.toString();
    } else {
      // Don't bother displaying version number for unsupported browsers as it's probably more error prone.
      document.getElementById("detected-browser").textContent = browser;
    }

    toggleDisplay(document.getElementsByClassName("no-js"), "hide");
    if (browser === "Firefox") {
      if (version >= minVersion.firefox) {
        // Supported Firefox
        toggleDisplay(document.getElementsByClassName("supported-browser"), "show");
        toggleDisplay(document.getElementsByClassName("chrome"), "hide");
        toggleDisplay(document.getElementsByClassName("firefox"), "show");
      } else {
        // Outdated Firefox
        toggleDisplay(document.getElementsByClassName("outdated-browser"), "show");
      }
    } else if (browser === "Chrome") {
      if (version >= minVersion.chrome) {
        // Supported Chrome
        toggleDisplay(document.getElementsByClassName("supported-browser"), "show");
        toggleDisplay(document.getElementsByClassName("firefox"), "hide");
        toggleDisplay(document.getElementsByClassName("chrome"), "show");
      } else {
        // Outdated Chrome
        toggleDisplay(document.getElementsByClassName("outdated-browser"), "show");
      }
    } else {
      toggleDisplay(document.getElementsByClassName("unsupported-browser"), "show");
    }
  }

  function toggleContinueLink(method, state) {
    if (method == "direct") {
      hide(document.getElementById("skip-download-direct"));
      hide(document.getElementById("skip-verification-direct"));
      hide(document.getElementById("next-direct"));
      show(document.getElementById(state));
    }
    if(method == "bittorrent") {
      hide(document.getElementById("skip-download-bittorrent"));
      hide(document.getElementById("next-bittorrent"));
      show(document.getElementById(state));
    }
  }

  function hitCounter(status) {
    try {
      var counter_url, url, scenario, version, cachebust;
      counter_url = "/install/download/counter";
      url = window.location.href.split("/");
      if (window.location.href.match(/\/upgrade\//)) {
        scenario = 'upgrade';
      } else {
        scenario = url[url.lastIndexOf("install") + 1];
      }
      version = document.getElementById("tails-version").textContent.replace("\n", "");
      cachebust = Math.round(new Date().getTime() / 1000);
      fetch(counter_url + "?scenario=" + scenario + "&version=" + version + "&status=" + status + "&cachebust=" + cachebust);
    } catch (e) { } // Ignore if we fail to hit the download counter
  }

  function resetVerificationResult(result) {
    hide(document.getElementById("verifying-download"));
    hide(document.getElementById("verification-successful"));
    hide(document.getElementById("verification-failed"));
    hide(document.getElementById("verification-failed-again"));
    toggleContinueLink("direct", "skip-verification-direct");
  }

  function showUpdateExtension() {
    hide(document.getElementById("verification"));
    hide(document.getElementById("install-extension"));
    show(document.getElementById("update-extension"));
  }

  function showVerifyDownload() {
    hide(document.getElementById("install-extension"));
    hide(document.getElementById("update-extension"));
    show(document.getElementById("verification"));
  }

  function showVerifyingDownload(filename) {
    hide(document.getElementById("verify-download-wrapper"));
    if (filename) {
      document.getElementById("filename").textContent = filename;
    }
    show(document.getElementById("verifying-download"));
  }

  function showVerificationProgress(percentage) {
    showVerifyingDownload();
    document.getElementById("progress-bar").style.width = percentage + "%";
    document.getElementById("progress-bar").setAttribute("aria-valuenow", percentage.toString());
  }

  function showVerificationResult(result) {
    toggleDirectBitTorrent("direct");
    showVerifyDownload();
    hide(document.getElementById("verify-download-wrapper"));
    resetVerificationResult();
    hitCounter(result);
    if (result === "successful") {
      show(document.getElementById("verification-successful"));
      opaque(document.getElementById("step-continue-direct"));
      toggleContinueLink("direct", "next-direct");
    }
    else if (result === "failed") {
      show(document.getElementById("verification-failed"));
      // Try again with different mirrors
      toggleDisplay(document.getElementsByClassName("use-mirror-pool"), "hide");
      toggleDisplay(document.getElementsByClassName("use-mirror-pool-on-retry"), "show");
      replaceUrlPrefixWithRandomMirror(document.querySelectorAll(".use-mirror-pool-on-retry"));
    }
    else if (result === "failed-again") {
      show(document.getElementById("verification-failed-again"));
    }
  }

  function toggleDirectBitTorrent(method) {
    transparent(document.getElementById("step-verify-direct"));
    transparent(document.getElementById("step-continue-direct"));
    transparent(document.getElementById("continue-link-direct"));
    transparent(document.getElementById("step-verify-bittorrent"));
    transparent(document.getElementById("step-continue-bittorrent"));
    transparent(document.getElementById("continue-link-bittorrent"));
    if (method == "direct") {
      opaque(document.getElementById("step-verify-direct"));
      opaque(document.getElementById("continue-link-direct"));
      show(document.getElementById("verify-download-wrapper"));
    }
    if (method == "bittorrent") {
      opaque(document.getElementById("step-verify-bittorrent"));
      opaque(document.getElementById("step-continue-bittorrent"));
      opaque(document.getElementById("continue-link-bittorrent"));
      toggleContinueLink("bittorrent", "next-bittorrent");
    }
  }

  // Reset the page to its initial state:
  // - Detect the browser version and display the relevant variant
  detectBrowser();
  // - Show the download steps of both direct and BitTorrent downloads
  toggleDirectBitTorrent("none");
  // - Display 'Skip download' as continue link
  toggleContinueLink("direct", "skip-download-direct");
  toggleContinueLink("bittorrent", "skip-download-bittorrent");
  opaque(document.getElementById("continue-link-direct"));
  opaque(document.getElementById("continue-link-bittorrent"));

  // Display "Verify with your browser" when image is clicked
  document.getElementById("download-img").onclick = function(e) { displayVerificationExtension(e, this); }
  document.getElementById("download-iso").onclick = function(e) { displayVerificationExtension(e, this); }

  function displayVerificationExtension(e, elm) {
    try {
      e.preventDefault();
      hitCounter("download-image");
      toggleDirectBitTorrent("direct");
      resetVerificationResult();
    } finally {
      // Setting window.location.href will abort AJAX requests resulting
      // in a NetworkError depending on the timing and browser.
      window.open(elm.getAttribute("href"), "_blank");
    }
  }

  // Display "Verify with your browser" when "I already" is clicked
  document.getElementById("already-downloaded").onclick = function() {
    hitCounter("already-downloaded");
    toggleDirectBitTorrent("direct");
    resetVerificationResult();
  }

  // Reset verification when downloading again after failure
  document.getElementById("download-img-again").onclick = function(e) { resetVerification(e, this); }
  document.getElementById("download-iso-again").onclick = function(e) { resetVerification(e, this); }

  function resetVerification(e, elm) {
    try {
      e.preventDefault();
      hitCounter("download-image-again");
      toggleDirectBitTorrent("direct");
      resetVerificationResult();
    } finally {
      // Setting window.location.href will abort AJAX requests resulting
      // in a NetworkError depending on the timing and browser.
      window.open(elm.getAttribute("href"), "_blank");
    }
  }

  // Display "Verify with BitTorrent" when Torrent file is clicked
  document.getElementById("download-img-torrent").onclick = function(e) { displayBitTorrentVerification(e, this); }
  document.getElementById("download-iso-torrent").onclick = function(e) { displayBitTorrentVerification(e, this); }

  function displayBitTorrentVerification(e, elm) {
    try {
      e.preventDefault();
      hitCounter("download-torrent");
      toggleDirectBitTorrent("bittorrent");
    } finally {
      window.location = elm.getAttribute("href");
    }
  }

  // To debug the display of the different states:
  // showVerificationResult("successful");
  // showVerificationResult("failed");
  // showVerificationResult("failed-again");
  // showVerificationProgress('50');

});
