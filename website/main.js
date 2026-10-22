// Chinese copy lives in the HTML; English is provided here and swapped in by key.
const en = {
  "nav.features": "Features",
  "nav.plugins": "Custom plugins",
  "nav.privacy": "Privacy",
  "nav.install": "Install",
  "hero.badge": "v0.5.4 is out · Free &amp; open source",
  "hero.title": "Select text.<br><span class=\"grad\">AI is right there.</span>",
  "hero.lead": "PickLingo is a selection-first AI assistant for macOS. Select text in almost any app and a toolbar appears right at your pointer: translate, explain, polish, summarize, or run plugins you build yourself.",
  "hero.download": "Download for macOS — free",
  "hero.source": "View source",
  "hero.meta": "macOS 14+ · Universal for Apple Silicon &amp; Intel · Works with any OpenAI-compatible service",
  "hero.sound": "🔊 Play with sound",
  "hero.mute": "🔇 Mute",
  "strip.zero": "Zero",
  "strip.zeroDesc": "copy-paste or window switching",
  "strip.pluginsDesc": "built-in + your own plugins",
  "strip.apps": "Any app",
  "strip.appsDesc": "browsers, Office, PDFs, editors",
  "strip.key": "Your key",
  "strip.keyDesc": "talks directly to the model you choose",
  "features.eyebrow": "Features",
  "features.title": "Help wherever you read",
  "features.lead": "Every screenshot below is PickLingo running in a real app.",
  "f1.title": "Select to translate",
  "f1.body": "Select a sentence in Chrome, Safari, Word, Zotero and more — the toolbar pops up where you released the mouse. Click Translate and the result streams in, with the original right above it.",
  "f1.p1": "Detects the source language; switch the target anytime",
  "f1.p2": "Follows your pointer without covering what you read",
  "f2.title": "Polish, then replace in place",
  "f2.body": "Writing a report or an email? Select a paragraph, click Polish for a cleaner version, then Replace to write it straight back into your document.",
  "f2.p1": "Copy, insert, replace, regenerate, follow up",
  "f2.p2": "Keeps your selection in native editors",
  "f2.cap1": "Polished result",
  "f2.cap2": "After one-click replace",
  "f3.title": "Explain terms inside PDFs",
  "f3.body": "Reading papers in Preview or Zotero? Select an unfamiliar term and click Explain. A follow-up box lets you keep digging.",
  "f3.p1": "Reads selections from web engines and PDF readers",
  "f3.p2": "Markdown rendering and partial copy in results",
  "plugins.eyebrow": "Custom plugins",
  "plugins.title": "One prompt, <span class=\"grad\">one new tool</span>",
  "plugins.lead": "Turn the things you repeat every day into plugins — they show up in the selection toolbar instantly. Here is a “Reply to email” plugin built in 30 seconds.",
  "ps1.title": "Create a plugin",
  "ps1.body": "Name it, pick an icon, write a prompt, and turn on “Requires user input”.",
  "ps2.title": "Select the email, jot your points",
  "ps2.body": "The new plugin is already in the toolbar; it asks for your key points first.",
  "ps3.title": "Get a polished reply",
  "ps3.body": "Your notes plus the original email become a reply ready to send.",
  "prompt.name": "Reply to email",
  "prompt.code": "Using my key points “<em>{user_input}</em>”, write a polite, concise reply to the email below. Output only the body: <em>{selected_text}</em>",
  "cap1.t": "Two execution modes",
  "cap1.b": "AI plugins call your model; local action plugins run shell commands — open a selected path, search a selected word, and more.",
  "cap2.t": "Placeholders",
  "cap2.b": "{selected_text}, {user_input}, {source}/{target} — values are escaped automatically so commands stay safe.",
  "cap3.t": "Interaction on demand",
  "cap3.b": "Ask for extra input, show language controls, and choose which result actions appear: copy, insert, replace, follow up.",
  "cap4.t": "Order and toggles",
  "cap4.b": "Drag to reorder and enable or disable anytime — even built-in prompts are editable.",
  "ideas.title": "More ideas:",
  "ideas.1": "Extract to-dos",
  "ideas.2": "Explain code",
  "ideas.3": "Search scholar",
  "ideas.4": "Glossary cards",
  "ideas.5": "Business English",
  "ideas.6": "Git commit message",
  "ideas.7": "Open path in Terminal",
  "qa.title": "Double-tap ⌘ to ask anything",
  "qa.body": "No selection needed. Double-tap Command anywhere, type a question, get an answer — and keep the conversation going.",
  "st.title": "Four styles. Placement your way.",
  "st.body": "Floating Circles, Frosted Capsule, Minimal Bar, and Icon &amp; Text. The toolbar is anchored to your mouse release point, with live previews for spacing and offsets.",
  "apps.eyebrow": "Works with the apps you use",
  "apps.note": "PickLingo reads selections through macOS Accessibility: native controls, Chromium/Electron, WebKit and Gecko. For the rare app that hides its selection, copy the text and choose “Process Copied Text” from the menu bar.",
  "privacy.eyebrow": "Privacy &amp; control",
  "privacy.title": "Your words, your rules",
  "pv1.t": "Hands off your clipboard",
  "pv1.b": "Selection uses Accessibility only — no simulated ⌘C, no clipboard rewrites, no fights with terminal copy-on-select.",
  "pv2.t": "Bring your own model",
  "pv2.b": "Standard OpenAI Chat Completions with any compatible service or local model. Settings stay on your Mac and requests go straight to the endpoint you enter — no relay servers.",
  "pv3.t": "Sensitive fields skipped",
  "pv3.b": "Password and secure fields are never read. Blacklist any app, and it stays off across restarts.",
  "pv4.t": "Open source",
  "pv4.b": "Licensed under GPL-3.0. Read, build, and modify every line.",
  "install.eyebrow": "Three steps",
  "install.title": "Up and running in a minute",
  "i1.t": "Download and install",
  "i1.b": "Open the DMG and drag PickLingo into Applications.",
  "i2.t": "Allow it to open",
  "i2.b": "If macOS blocks the first launch, choose “Open Anyway” in System Settings › Privacy &amp; Security, then grant Accessibility permission when asked.",
  "i3.t": "Add your model",
  "i3.b": "Enter your API key, base URL, and model in Settings, click Test Connection, and go select some text.",
  "install.download": "Download PickLingo",
  "install.notes": "Release notes",
  "faq.title": "FAQ",
  "q1.q": "Is PickLingo free?",
  "q1.a": "The app is free and open source. AI costs depend on the model service you choose — or use a local model.",
  "q2.q": "The toolbar doesn’t appear in an app. What now?",
  "q2.a": "Make sure Accessibility permission is granted and the app isn’t blacklisted. A few apps (some terminals and canvas apps) don’t expose selections; copy the text and use “Process Copied Text” from the menu bar.",
  "q3.q": "Which models are supported?",
  "q3.a": "Any service compatible with OpenAI Chat Completions, including HTTP/HTTPS gateways with path prefixes. Save multiple presets, switch anytime, with streaming and Think Mode.",
  "q4.q": "Does Replace touch my clipboard?",
  "q4.a": "Insert and Replace work by pasting, so the result stays on your clipboard for reuse. Normal selection never reads or writes the clipboard.",
  "footer.text": "Open source under GPL-3.0 · Made for macOS",
};

const nodes = [...document.querySelectorAll("[data-i18n]")];
const zh = Object.fromEntries(nodes.map(n => [n.dataset.i18n, n.innerHTML]));
zh["hero.mute"] = "🔇 静音";
const toggle = document.getElementById("lang-toggle");

function apply(lang) {
  const dict = lang === "en" ? en : zh;
  for (const n of nodes) {
    const value = dict[n.dataset.i18n];
    if (value !== undefined) n.innerHTML = value;
  }
  document.documentElement.lang = lang === "en" ? "en" : "zh-CN";
  document.title = lang === "en" ? "PickLingo — Select text. AI is right there." : "PickLingo — 选中文字，AI 就在指尖";
  toggle.textContent = lang === "en" ? "中文" : "EN";
  localStorage.setItem("picklingo-lang", lang);
}

const saved = localStorage.getItem("picklingo-lang");
apply(saved || (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en"));
toggle.addEventListener("click", () => apply(document.documentElement.lang === "en" ? "zh" : "en"));

// Reveal sections as they scroll into view.
const observer = new IntersectionObserver(entries => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); observer.unobserve(e.target); }
}, { threshold: 0.12 });
document.querySelectorAll(".reveal").forEach(el => observer.observe(el));

const video = document.getElementById("promo");
// Autoplay must start muted; the first click restarts the film with its soundtrack.
const sound = document.getElementById("sound");
sound.addEventListener("click", () => {
  if (video.muted) { video.muted = false; video.currentTime = 0; video.play(); }
  else video.muted = true;
  const key = video.muted ? "hero.sound" : "hero.mute";
  sound.dataset.i18n = key;
  sound.innerHTML = (document.documentElement.lang === "en" ? en : zh)[key] ?? "🔇 静音";
});
