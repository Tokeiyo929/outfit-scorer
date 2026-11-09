"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fs = require("fs");
const path = require("path");
const cache = require("./cache").default;
const build = require("../../core/build");
const CHANNEL_KEYS = [
    "common",
    "common_min",
    "applovin",
    "ironsource",
    "ironsource2025",
    "mintegral",
    "unity",
    "google",
    "google_portrait",
    "google_landscape",
    "facebook",
    "facebook_split_zip",
    "pangle",
    "pangle_portrait",
    "pangle_landscape",
    "liftoff",
    "moloco",
    "tiktok",
    "vungle",
    "bigo",
    "kwai",
    "nefta",
    "nefta_zip"
];
function getProjectPath() {
    if (typeof Editor !== "undefined") {
        if (Editor.Project && Editor.Project.path)
            return Editor.Project.path;
        if (Editor.projectPath)
            return Editor.projectPath;
    }
    return process.cwd();
}
function getChannelConfig() {
    const configPath = path.join(getProjectPath(), "settings", "super-html-channels.json");
    if (!fs.existsSync(configPath))
        return null;
    return JSON.parse(fs.readFileSync(configPath, "utf8"));
}
function getChannelKey(adapter) {
    if (adapter.s_name === "facebook" && adapter.b_out_zip && adapter.b_split_res)
        return "facebook_split_zip";
    if (adapter.s_name === "nefta" && adapter.b_out_zip)
        return "nefta_zip";
    return adapter.s_config_name || adapter.s_name;
}
function applyEnabledChannels() {
    const channelConfig = getChannelConfig();
    if (!channelConfig)
        return;
    const enabledChannels = channelConfig.enabled_channels;
    if (!enabledChannels || typeof enabledChannels !== "object")
        return;
    build.config.inject_channel_adapter.forEach(adapter => {
        adapter.b_enable = enabledChannels[getChannelKey(adapter)] === true;
    });
}
class CocosMain {
    constructor(version, dest, cb) {
        const config = cache.get();
        this.s_version = version;
        this.s_input_dir = dest;
        this.cb = cb;
        build.config.is_obfuscator = config.enable_obfuscator;
        applyEnabledChannels();
        new build.default(version, dest, path.join(dest, "../", "super-html"), cb);
    }
}
CocosMain.CHANNEL_KEYS = CHANNEL_KEYS;
exports.default = CocosMain;
