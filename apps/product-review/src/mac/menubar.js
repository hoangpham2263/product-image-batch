// Star in the macOS menu bar while the app runs: Mở cửa sổ / Thoát. Started by server.mjs with
// `osascript -l JavaScript`; it quits by itself once the server stops answering.
ObjC.import("Cocoa");
const env = $.NSProcessInfo.processInfo.environment;
const base = "http://127.0.0.1:" + env.objectForKey("PRB_PORT").js;
const app = $.NSApplication.sharedApplication;
app.setActivationPolicy(1); // accessory: no Dock icon, menu bar item only

function request(path, method) {
  const req = $.NSMutableURLRequest.requestWithURL($.NSURL.URLWithString(base + path));
  req.setHTTPMethod(method || "GET");
  req.setTimeoutInterval(3);
  const data = $.NSURLConnection.sendSynchronousRequestReturningResponseError(req, null, null);
  return !data.isNil();
}

ObjC.registerSubclass({
  name: "PRBMenuTarget",
  methods: {
    "open:": { types: ["void", ["id"]], implementation: function () { request("/api/open", "POST"); } },
    "quit:": { types: ["void", ["id"]], implementation: function () { request("/api/quit", "POST"); app.terminate(null); } },
    "tick:": { types: ["void", ["id"]], implementation: function () { if (!request("/api/root")) app.terminate(null); } },
  },
});
const target = $.PRBMenuTarget.alloc.init;

const item = $.NSStatusBar.systemStatusBar.statusItemWithLength(-1);
const star = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription("star.fill", "Product Review");
if (star.isNil()) item.button.setTitle("★");
else { star.setTemplate(true); item.button.setImage(star); }
item.button.setToolTip("Product Review");

const menu = $.NSMenu.alloc.init;
menu.setAutoenablesItems(false);
const name = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent("Product Review", null, "");
name.setEnabled(false);
menu.addItem(name);
menu.addItem($.NSMenuItem.separatorItem);
for (const [title, action] of [["Mở cửa sổ", "open:"], ["Thoát", "quit:"]]) {
  const entry = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(title, action, "");
  entry.setTarget(target);
  menu.addItem(entry);
}
item.setMenu(menu);

$.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(5, target, "tick:", null, true);
app.run;
