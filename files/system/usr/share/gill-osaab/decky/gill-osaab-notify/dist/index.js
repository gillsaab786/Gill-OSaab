const manifest = {"name":"Gill-OSaab Notifications"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const addEventListener = api.addEventListener;
const removeEventListener = api.removeEventListener;
const toaster = api.toaster;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

var DefaultContext = {
  color: undefined,
  size: undefined,
  className: undefined,
  style: undefined,
  attr: undefined
};
var IconContext = SP_REACT.createContext && /*#__PURE__*/SP_REACT.createContext(DefaultContext);

var _excluded = ["attr", "size", "title"];
function _objectWithoutProperties(e, t) { if (null == e) return {}; var o, r, i = _objectWithoutPropertiesLoose(e, t); if (Object.getOwnPropertySymbols) { var n = Object.getOwnPropertySymbols(e); for (r = 0; r < n.length; r++) o = n[r], -1 === t.indexOf(o) && {}.propertyIsEnumerable.call(e, o) && (i[o] = e[o]); } return i; }
function _objectWithoutPropertiesLoose(r, e) { if (null == r) return {}; var t = {}; for (var n in r) if ({}.hasOwnProperty.call(r, n)) { if (-1 !== e.indexOf(n)) continue; t[n] = r[n]; } return t; }
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function ownKeys(e, r) { var t = Object.keys(e); if (Object.getOwnPropertySymbols) { var o = Object.getOwnPropertySymbols(e); r && (o = o.filter(function (r) { return Object.getOwnPropertyDescriptor(e, r).enumerable; })), t.push.apply(t, o); } return t; }
function _objectSpread(e) { for (var r = 1; r < arguments.length; r++) { var t = null != arguments[r] ? arguments[r] : {}; r % 2 ? ownKeys(Object(t), true).forEach(function (r) { _defineProperty(e, r, t[r]); }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function (r) { Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r)); }); } return e; }
function _defineProperty(e, r, t) { return (r = _toPropertyKey(r)) in e ? Object.defineProperty(e, r, { value: t, enumerable: true, configurable: true, writable: true }) : e[r] = t, e; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == typeof i ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != typeof t || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r); if ("object" != typeof i) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }
function Tree2Element(tree) {
  return tree && tree.map((node, i) => /*#__PURE__*/SP_REACT.createElement(node.tag, _objectSpread({
    key: i
  }, node.attr), Tree2Element(node.child)));
}
function GenIcon(data) {
  return props => /*#__PURE__*/SP_REACT.createElement(IconBase, _extends({
    attr: _objectSpread({}, data.attr)
  }, props), Tree2Element(data.child));
}
function IconBase(props) {
  var elem = conf => {
    var attr = props.attr,
      size = props.size,
      title = props.title,
      svgProps = _objectWithoutProperties(props, _excluded);
    var computedSize = size || conf.size || "1em";
    var className;
    if (conf.className) className = conf.className;
    if (props.className) className = (className ? className + " " : "") + props.className;
    return /*#__PURE__*/SP_REACT.createElement("svg", _extends({
      stroke: "currentColor",
      fill: "currentColor",
      strokeWidth: "0"
    }, conf.attr, attr, svgProps, {
      className: className,
      style: _objectSpread(_objectSpread({
        color: props.color || conf.color
      }, conf.style), props.style),
      height: computedSize,
      width: computedSize,
      xmlns: "http://www.w3.org/2000/svg"
    }), title && /*#__PURE__*/SP_REACT.createElement("title", null, title), props.children);
  };
  return IconContext !== undefined ? /*#__PURE__*/SP_REACT.createElement(IconContext.Consumer, null, conf => elem(conf)) : elem(DefaultContext);
}

// THIS FILE IS AUTO GENERATED
function FaBell (props) {
  return GenIcon({"attr":{"viewBox":"0 0 448 512"},"child":[{"tag":"path","attr":{"d":"M224 512c35.32 0 63.97-28.65 63.97-64H160.03c0 35.35 28.65 64 63.97 64zm215.39-149.71c-19.32-20.76-55.47-51.99-55.47-154.29 0-77.7-54.48-139.9-127.94-155.16V32c0-17.67-14.32-32-31.98-32s-31.98 14.33-31.98 32v20.84C118.56 68.1 64.08 130.3 64.08 208c0 102.3-36.15 133.53-55.47 154.29-6 6.45-8.66 14.16-8.61 21.71.11 16.4 12.98 32 32.1 32h383.8c19.12 0 32-15.6 32.1-32 .05-7.55-2.61-15.27-8.61-21.71z"},"child":[]}]})(props);
}

const getState = callable("get_state");
const dismiss = callable("dismiss");
const cancel = callable("cancel");
const clearAll = callable("clear");
// ------------------------------------------------------------ shared store
let current = { items: [] };
const subscribers = new Set();
const lastToasted = new Map();
function publish(s) {
    current = s && Array.isArray(s.items) ? s : { items: [] };
    subscribers.forEach((fn) => fn(current));
}
function isRunning(i) {
    return i.state === "active" || i.state === "paused";
}
function toastText(i) {
    if (i.state === "failed")
        return i.body ? `Failed: ${i.body}` : "Failed";
    if (i.state === "done" && i.kind !== "notification")
        return "Finished";
    const pct = isRunning(i) && i.percent != null ? ` · ${i.percent}%` : "";
    return (i.body || i.app || "") + pct;
}
/** Pop-ups like Android: when something new appears and when it finishes or fails. */
function toastChanges(s, firstLoad) {
    const shown = [];
    for (const i of s.items) {
        const prev = lastToasted.get(i.id);
        if (prev === i.state)
            continue;
        lastToasted.set(i.id, i.state);
        if (firstLoad)
            continue; // don't replay old history when Game Mode starts
        const isNew = prev === undefined;
        const finished = i.state === "done" || i.state === "failed";
        if (isNew || finished) {
            shown.push(i);
            toaster.toast({
                title: i.title || i.app || "Notification",
                body: toastText(i),
                duration: i.state === "failed" ? 6000 : 4000,
                critical: i.state === "failed",
            });
        }
    }
    return shown;
}
function useHubState() {
    const [state, setState] = SP_REACT.useState(current);
    SP_REACT.useEffect(() => {
        subscribers.add(setState);
        return () => {
            subscribers.delete(setState);
        };
    }, []);
    return state;
}
// ------------------------------------------------------------ Quick Access tab
function Content() {
    const { items } = useHubState();
    const running = items.filter(isRunning);
    const recent = items.filter((i) => !isRunning(i));
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "In progress", children: [running.length === 0 && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: "Nothing running", description: "Downloads, copies and installs show here." }) })), running.map((i) => (SP_JSX.jsxs(DFL.PanelSectionRow, { children: [SP_JSX.jsx(DFL.ProgressBarWithInfo, { label: i.title || i.app, description: [i.body, i.detail].filter(Boolean).join(" · "), nProgress: i.percent ?? 0, indeterminate: i.percent == null, sOperationText: i.state === "paused" ? "Paused" : i.percent != null ? `${i.percent}%` : "Working…" }), i.cancellable && (SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => cancel(i.id), children: "Cancel" }))] }, i.id)))] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Notifications", children: [recent.length === 0 && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: "No notifications" }) })), recent.map((i) => (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "inline", label: i.title || i.app, description: i.state === "failed" ? `Failed${i.body ? ": " + i.body : ""}` : i.body, onClick: () => dismiss(i.id), children: "Dismiss" }) }, i.id))), recent.length > 0 && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => clearAll(), children: "Clear all" }) }))] })] }));
}
var index = definePlugin(() => {
    let firstLoad = true;
    const onState = (s) => {
        toastChanges(s, firstLoad);
        firstLoad = false;
        publish(s);
    };
    const listener = addEventListener("gosaab_state", onState);
    getState().then(onState).catch(() => undefined);
    return {
        name: "Gill-OSaab Notifications",
        titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: "Notifications" }),
        content: SP_JSX.jsx(Content, {}),
        icon: SP_JSX.jsx(FaBell, {}),
        onDismount() {
            removeEventListener("gosaab_state", listener);
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
