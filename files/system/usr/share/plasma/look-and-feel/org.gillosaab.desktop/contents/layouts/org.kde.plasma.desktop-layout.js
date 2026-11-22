// Gill-OSaab desktop layout (Plasma 6 scripting API).
// macOS/iOS-inspired: a slim top bar with app menu, tray and clock,
// and a floating, centred dock that moves out of the way of windows.

function setIf(obj, prop, value) {
    try { obj[prop] = value; } catch (e) { print("gill-osaab: cannot set " + prop + ": " + e); }
}

function addLaunchers(tasks, ids) {
    // file manager and browser always resolve to whatever the system default is
    var launchers = ["preferred://filemanager", "preferred://browser"];
    for (var i = 0; i < ids.length; i++) {
        if (applicationExists(ids[i])) {
            launchers.push("applications:" + ids[i]);
        }
    }
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", launchers);
    tasks.writeConfig("showOnlyCurrentDesktop", false);
    tasks.writeConfig("groupingStrategy", 1);
    tasks.writeConfig("indicateAudioStreams", true);
    tasks.writeConfig("iconSpacing", 2);
    tasks.writeConfig("maxStripes", 1);
}

// ---------------------------------------------------------------- top bar
var topBar = new Panel;
topBar.location = "top";
topBar.height = Math.round(gridUnit * 1.6);
setIf(topBar, "floating", false);
setIf(topBar, "hiding", "none");

var launcherMenu = topBar.addWidget("org.kde.plasma.kickoff");
launcherMenu.currentConfigGroup = ["General"];
launcherMenu.writeConfig("icon", "gill-osaab");
launcherMenu.writeConfig("favoritesPortedToKAstats", true);

topBar.addWidget("org.kde.plasma.appmenu");
topBar.addWidget("org.kde.plasma.panelspacer");

var tray = topBar.addWidget("org.kde.plasma.systemtray");

var clock = topBar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BesideTime");
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");
clock.writeConfig("use24hFormat", 0);

// ---------------------------------------------------------------- dock
var dock = new Panel;
dock.location = "bottom";
dock.height = Math.round(gridUnit * 3.4);
setIf(dock, "floating", true);
setIf(dock, "lengthMode", "fit");
setIf(dock, "alignment", "center");
setIf(dock, "hiding", "dodgewindows");

var tasks = dock.addWidget("org.kde.plasma.icontasks");
addLaunchers(tasks, [
    "steam.desktop",
    "gosaab-settings.desktop",
    "systemsettings.desktop"
]);
dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.trash");

// ---------------------------------------------------------------- wallpaper
var allDesktops = desktops();
for (var d = 0; d < allDesktops.length; d++) {
    var desk = allDesktops[d];
    desk.wallpaperPlugin = "org.kde.image";
    desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desk.writeConfig("Image", "file:///usr/share/wallpapers/GillOSaab/");
}
