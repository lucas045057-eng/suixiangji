// Audited against origin/main on 2026-10-09. See docs/PRODUCT-AUDIT.md.
export const siteConfig = {
  name: "随想记",
  tagline: "极简至上，越用越懂你的 AI 记账",
  description:
    "随想记是一款极简的个人记账与财务管理应用，通过 AI 逐渐理解你的使用习惯，让记录、整理和回顾财务变得越来越简单。",
  siteUrl: "https://suixiangji.icu/",
  github: "https://github.com/lucas045057-eng/suixiangji",
  year: 2026,
  release: {
    tag: "v1.0.8",
    url: "https://github.com/lucas045057-eng/suixiangji/releases/tag/v1.0.8",
    checkedAt: "2026-10-30",
    sourceHead: "c98963f",
  },
  downloads: {
    android: {
      enabled: true,
      artifactVerified: true,
      version: "1.0.8",
      build: 12,
      url: "https://download.suixiangji.icu/app/suixiangji-v1.0.8-build12.apk",
      file: "suixiangji-v1.0.8-build12.apk",
      size: "76.4 MB",
      sizeBytes: 80149724,
      sha256: "458f2cae6e8b7a0a61b06d6d70a9202ff4ccc98319ad849766c428f28418b834",
    },
    windows: {
      enabled: false,
      artifactVerified: false,
      version: "",
      url: "",
      file: "",
      size: "",
      sizeBytes: 0,
      unavailableLabel: "Windows 版整理中",
    },
  },
  // Local image paths, relative to index.html. Empty paths keep the CSS mockup.
  screenshots: { android: "", windows: "", og: "assets/images/og-image.png" },
  aiFeatures: {
    recurringExpenses: {
      status: "PLANNED",
      label: "正在打磨",
      note: "固定支出发现为产品方向，当前版本尚未提供。",
    },
    ledgerCleanup: { status: "PLANNED", label: "正在打磨", note: "账本清理为产品方向，当前版本尚未提供。" },
    refundMatching: {
      status: "PLANNED",
      label: "正在打磨",
      note: "退款自动配对为产品方向，当前版本尚未提供。",
    },
    sharedExpenseUnderstanding: {
      status: "PLANNED",
      label: "正在打磨",
      note: "AA 与垫付净支出识别为产品方向，当前版本尚未提供。",
    },
    spendingAttribution: {
      status: "PARTIAL",
      label: "逐步完善",
      note: "已有分类统计与月报；一句话解释具体消费变化正在打磨。",
    },
    adaptiveCategories: {
      status: "PARTIAL",
      label: "逐步完善",
      note: "已有自定义分类与确认后的分类记忆；自动整理分类正在打磨。",
    },
    personalAliases: {
      status: "PARTIAL",
      label: "已有确认记忆",
      note: "当前会记住已确认表达对应的分类与账户；地点含义理解与省略金额单位的写法正在打磨。",
    },
  },
};

export function safeHttpsUrl(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? url.href : null;
  } catch {
    return null;
  }
}

export function verifiedDownload(platform, config = siteConfig) {
  const item = config.downloads[platform];
  const url = safeHttpsUrl(item?.url);
  if (!item?.enabled || !item.artifactVerified || !url || !item.version || !item.sizeBytes) return null;
  const parsed = new URL(url);
  const repository = safeHttpsUrl(config.github);
  const releaseBase =
    repository && `${repository.replace(/\/$/, "")}/releases/download/${config.release.tag}/`;
  const selfHosted = url.startsWith("https://download.suixiangji.icu/app/");
  if (
    !selfHosted &&
    (!releaseBase ||
      !url.startsWith(releaseBase) ||
      decodeURIComponent(parsed.pathname.split("/").pop()) !== item.file)
  )
    return null;
  if (platform === "android" && !/\.apk$/i.test(item.file)) return null;
  if (platform === "windows" && !/\.(exe|msix|msixbundle|zip)$/i.test(item.file)) return null;
  return { ...item, url };
}
