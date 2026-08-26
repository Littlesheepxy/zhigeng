export const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://zhigeng.app").replace(/\/$/, "");

/** 同域直链，实际文件在对象存储；不要链到 GitHub 页面。 */
export const macDownloadUrl = "/Zhigeng-mac-arm64.dmg";
export const macDownloadFilename = "Zhigeng-mac-arm64.dmg";

export const sourceUrl = "https://github.com/Littlesheepxy/fold-one";
