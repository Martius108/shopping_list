"use strict";
const english = !navigator.language.toLowerCase().startsWith("de");
const text = (id, value) => { document.getElementById(id).textContent = value; };
if (english) {
  document.documentElement.lang = "en";
  document.title = "Shopping List · Invitation";
  document.querySelector(".brand").textContent = "Shopping List";
  text("title", "Invitation to a shopping list");
  text("intro", "Open the complete link from your invitation email.");
  text("open", "Open Shopping List");
  text("install-title", "App not installed yet?");
  text("install", "Ask the sender for Shopping List and install the app, then open this invitation again. You do not need a second account for another device of your own.");
  text("privacy", "Shopping List checks your access. This link alone does not grant access to a list.");
  document.querySelectorAll("li").forEach((item, index) => { item.textContent = ["Sign in with the invited email or create a Shopping List account.", "For a new account, confirm your email and return to the app.", "The shared list opens automatically."][index]; });
}
function renderInvitation() {
  document.getElementById("invitation").hidden = true;
  try {
  if (location.hash.length > 16384) throw new Error();
  const params = new URLSearchParams(location.hash.slice(1));
  const fields = [...params.keys()];
  const id = params.get("list") || "", name = params.get("name") || "", email = params.get("email") || "";
  if (fields.length !== 3 || new Set(fields).size !== 3 || !fields.every(key => ["list","name","email"].includes(key)) || !/^[A-Za-z0-9_-]{1,128}$/.test(id) || !name.trim() || name.length > 1000 || /[\u0000-\u001f\u007f]/.test(name) || email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Error();
  text("intro", english ? "Continue securely in the Shopping List app." : "Fahre sicher in der App Einkaufsliste fort.");
  text("list-name", name);
  text("account", (english ? "Invited email: " : "Eingeladene E-Mail-Adresse: ") + email);
  document.getElementById("open").href = "shoppinglist://invite/1?" + params.toString().replace(/\+/g, "%20");
  document.getElementById("invitation").hidden = false;
} catch (_) {
  text("intro", english ? "This invitation is incomplete or invalid. Ask the sender for a new invitation." : "Diese Einladung ist unvollständig oder ungültig. Bitte den Absender um eine neue Einladung.");
}

}
renderInvitation();
window.addEventListener("hashchange", renderInvitation);
