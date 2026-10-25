"use strict";
if (!navigator.language.toLowerCase().startsWith("de")) {
  document.documentElement.lang = "en";
  document.title = "Shopping List · Sign in";
  document.querySelector(".brand").textContent = "Shopping List";
  document.getElementById("title").textContent = "Sign in to Shopping List";
  document.getElementById("intro").textContent = "Open the sign-in link on the device where you requested it. Shopping List must already be installed there.";
}
