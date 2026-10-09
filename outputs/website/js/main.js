import { siteConfig, safeHttpsUrl, verifiedDownload } from "./site-config.js";

document.querySelectorAll("[data-brand]").forEach((el) => {
  el.textContent = siteConfig.name;
});
document.querySelectorAll("[data-tagline]").forEach((el) => {
  el.textContent = `${siteConfig.tagline}。`;
});
document.querySelector("[data-copyright]").textContent = `© ${siteConfig.year} ${siteConfig.name}`;
for (const [selector, value] of [
  ["[data-github]", siteConfig.github],
  ["[data-release]", siteConfig.release.url],
]) {
  const url = safeHttpsUrl(value);
  document.querySelectorAll(selector).forEach((el) => {
    if (url) el.href = url;
    else {
      el.removeAttribute("href");
      el.setAttribute("aria-disabled", "true");
    }
  });
}
document.querySelectorAll("[data-feature]").forEach((el) => {
  const feature = siteConfig.aiFeatures[el.dataset.feature];
  el.textContent = feature.label;
  el.dataset.status = feature.status;
  el.title = feature.note;
});
document.querySelectorAll("[data-feature-note]").forEach((el) => {
  el.textContent = siteConfig.aiFeatures[el.dataset.featureNote].note;
});
for (const platform of ["android", "windows"]) {
  const slot = document.querySelector(`[data-download-slot="${platform}"]`);
  const item = verifiedDownload(platform);
  if (item) {
    const link = document.createElement("a");
    link.className = "button button-download";
    link.href = item.url;
    link.textContent = `下载 ${platform === "android" ? "Android" : "Windows"} 版`;
    const arrow = document.createElement("span");
    arrow.textContent = "↓";
    arrow.setAttribute("aria-hidden", "true");
    link.append(arrow);
    slot.replaceChildren(link);
    const meta = document.querySelector(`[data-download-meta="${platform}"]`);
    if (platform === "windows") {
      meta.className = "download-meta";
      meta.replaceChildren();
      for (const [label, value] of [
        ["当前版本", item.version],
        ["文件大小", item.size],
      ]) {
        const div = document.createElement("div");
        const dt = document.createElement("dt");
        dt.textContent = label;
        const dd = document.createElement("dd");
        dd.textContent = value;
        div.append(dt, dd);
        meta.append(div);
      }
      const card = slot.closest(".download-card");
      card.querySelector(".availability").textContent = "现在开始";
      card.querySelector(".download-subnote").textContent = "来自 GitHub Release 的安装包";
    } else {
      document.querySelector('[data-download-version="android"]').textContent =
        `${item.version} · Build ${item.build}`;
      document.querySelector('[data-download-size="android"]').textContent = item.size;
    }
  } else {
    const button = document.createElement("button");
    button.type = "button";
    button.disabled = true;
    button.className = "button button-download";
    button.textContent =
      siteConfig.downloads[platform].unavailableLabel ||
      `${platform === "android" ? "Android" : "Windows"} 版整理中`;
    slot.replaceChildren(button);
    const card = slot.closest(".download-card");
    card.querySelector(".availability").textContent = "稍后见";
    card.querySelector(".download-subnote").textContent = "当前暂无已核实的公开下载文件";
    if (platform === "android") document.querySelector('[data-download-meta="android"]').hidden = true;
    else document.querySelector("[data-windows-status]").textContent = button.textContent;
  }
}

// A failed or missing replacement screenshot always falls back to the CSS UI.
document.querySelectorAll("[data-screenshot]").forEach((img) => {
  const path = siteConfig.screenshots[img.dataset.screenshot];
  if (!path || /^(?:[a-z]+:|\/\/)/i.test(path)) return;
  const mockup = document.querySelector(`[data-mockup="${img.dataset.screenshot}"]`);
  img.addEventListener("load", () => {
    img.hidden = false;
    mockup.hidden = true;
  });
  img.addEventListener("error", () => {
    img.hidden = true;
    mockup.hidden = false;
  });
  img.src = path;
});

const header = document.querySelector(".site-header");
const menuToggle = document.querySelector(".menu-toggle");
const nav = document.querySelector(".primary-nav");
const mobileQuery = matchMedia("(max-width: 600px)");
const updateHeader = () => header.classList.toggle("scrolled", window.scrollY > 12);
addEventListener("scroll", updateHeader, { passive: true });
updateHeader();
function setMenu(open, returnFocus = false) {
  header.classList.toggle("menu-open", open);
  menuToggle.setAttribute("aria-expanded", String(open));
  menuToggle.setAttribute("aria-label", open ? "关闭导航菜单" : "打开导航菜单");
  if (mobileQuery.matches) nav.inert = !open;
  else nav.inert = false;
  if (returnFocus) menuToggle.focus();
}
setMenu(false);
menuToggle.addEventListener("click", () => setMenu(menuToggle.getAttribute("aria-expanded") !== "true"));
nav
  .querySelectorAll("a")
  .forEach((link) => link.addEventListener("click", () => setMenu(false, mobileQuery.matches)));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && header.classList.contains("menu-open")) setMenu(false, true);
});
document.addEventListener("click", (event) => {
  if (!header.contains(event.target) && header.classList.contains("menu-open")) setMenu(false);
});
mobileQuery.addEventListener("change", () => setMenu(false));

function selectTab(tab, focus = false) {
  const tablist = tab.closest('[role="tablist"]');
  const group = tablist.closest(".story, .alias-demo");
  tablist.querySelectorAll('[role="tab"]').forEach((item) => {
    const selected = item === tab;
    item.setAttribute("aria-selected", String(selected));
    item.tabIndex = selected ? 0 : -1;
    document.getElementById(item.getAttribute("aria-controls")).hidden = !selected;
    const copy = group.querySelector(`[data-text="${item.dataset.scene}"]`);
    if (copy) copy.hidden = !selected;
  });
  if (focus) tab.focus();
}
document.querySelectorAll('[role="tablist"]').forEach((tablist) => {
  const tabs = [...tablist.querySelectorAll('[role="tab"]')];
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", (event) => {
      let next;
      if (event.key === "ArrowRight") next = tabs[(tabs.indexOf(tab) + 1) % tabs.length];
      if (event.key === "ArrowLeft") next = tabs[(tabs.indexOf(tab) + tabs.length - 1) % tabs.length];
      if (event.key === "Home") next = tabs[0];
      if (event.key === "End") next = tabs.at(-1);
      if (next) {
        event.preventDefault();
        selectTab(next, true);
      }
    });
  });
});
document.querySelectorAll("[data-demo-action]").forEach((button) =>
  button.addEventListener("click", () => {
    switch (button.dataset.demoAction) {
      case "remember":
        document.querySelector("#recurring-result").textContent =
          "演示：已记住这三笔固定支出。实际功能正在打磨。";
        break;
      case "ignore":
        document.querySelector("#recurring-result").textContent = "演示：已忽略这次建议，不会写入任何账本。";
        break;
      case "cleanup": {
        const details = document.querySelector("#cleanup-details");
        details.hidden = !details.hidden;
        button.setAttribute("aria-expanded", String(!details.hidden));
        button.firstChild.textContent = details.hidden ? "看看 " : "收起 ";
        break;
      }
    }
  }),
);

if ("IntersectionObserver" in window && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08 },
  );
  document.querySelectorAll("[data-reveal]").forEach((el) => {
    el.classList.add("js-reveal");
    observer.observe(el);
  });
}
