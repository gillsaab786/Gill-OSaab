import {
  ButtonItem,
  Field,
  PanelSection,
  PanelSectionRow,
  ProgressBarWithInfo,
  SliderField,
  staticClasses,
} from "@decky/ui";
import { addEventListener, callable, definePlugin, removeEventListener, toaster } from "@decky/api";
import { useEffect, useState } from "react";
import { FaBell } from "react-icons/fa";

type ItemState = "active" | "paused" | "done" | "failed" | "info";

interface Item {
  id: number;
  app: string;
  title: string;
  body: string;
  detail?: string;
  percent: number | null;
  state: ItemState;
  kind: string;
  cancellable: boolean;
  updated: number;
}

interface HubState {
  items: Item[];
}

interface Battery {
  percent: number | null;
  charging: boolean;
  watts: number;
  minutes: number | null;
  text: string;
}

interface Device {
  volume: number;
  muted: boolean;
  brightness: number | null;
  battery: Battery | null;
  mode: string;
  watts: number;
}

const getState = callable<[], HubState>("get_state");
const getDevice = callable<[], Device>("get_device");
const setVolume = callable<[value: number], void>("set_volume");
const setBrightness = callable<[value: number], void>("set_brightness");
const dismiss = callable<[id: number], void>("dismiss");
const cancel = callable<[id: number], void>("cancel");
const clearAll = callable<[], void>("clear");

// ------------------------------------------------------------ shared store
let current: HubState = { items: [] };
const subscribers = new Set<(s: HubState) => void>();
const lastToasted = new Map<number, ItemState>();

function publish(s: HubState) {
  current = s && Array.isArray(s.items) ? s : { items: [] };
  subscribers.forEach((fn) => fn(current));
}

function isRunning(i: Item) {
  return i.state === "active" || i.state === "paused";
}

function toastText(i: Item): string {
  if (i.state === "failed") return i.body ? `Failed: ${i.body}` : "Failed";
  if (i.state === "done" && i.kind !== "notification") return "Finished";
  const pct = isRunning(i) && i.percent != null ? ` · ${i.percent}%` : "";
  return (i.body || i.app || "") + pct;
}

/** Pop-ups like Android: when something new appears and when it finishes or fails. */
function toastChanges(s: HubState, firstLoad: boolean): Item[] {
  const shown: Item[] = [];
  for (const i of s.items) {
    const prev = lastToasted.get(i.id);
    if (prev === i.state) continue;
    lastToasted.set(i.id, i.state);
    if (firstLoad) continue; // don't replay old history when Game Mode starts
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

function useHubState(): HubState {
  const [state, setState] = useState<HubState>(current);
  useEffect(() => {
    subscribers.add(setState);
    return () => {
      subscribers.delete(setState);
    };
  }, []);
  return state;
}

// ------------------------------------------------------------ volume, brightness, battery
function useDevice(): Device | null {
  const [dev, setDev] = useState<Device | null>(null);
  useEffect(() => {
    let alive = true;
    const load = () => getDevice().then((d) => alive && setDev(d)).catch(() => undefined);
    load();
    const timer = setInterval(load, 5000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);
  return dev;
}

function batteryLine(b: Battery): string {
  if (b.charging) return b.text ? `Charging · full in ${b.text}` : "Charging";
  return b.text ? `${b.text} left` : "Estimating…";
}

function QuickSettings({ dev }: { dev: Device | null }) {
  if (!dev) return null;
  return (
    <PanelSection title="Quick settings">
      <PanelSectionRow>
        <SliderField label="Volume" value={dev.muted ? 0 : dev.volume} min={0} max={100} step={5}
          showValue onChange={(v: number) => setVolume(v)} />
      </PanelSectionRow>
      {dev.brightness != null && (
        <PanelSectionRow>
          <SliderField label="Brightness" value={dev.brightness} min={5} max={100} step={5}
            showValue onChange={(v: number) => setBrightness(v)} />
        </PanelSectionRow>
      )}
    </PanelSection>
  );
}

function BatterySection({ dev }: { dev: Device | null }) {
  const b = dev?.battery;
  if (!b) return null;
  const how = [dev?.mode, dev?.watts ? `${dev.watts} W` : "", b.watts ? `using ${b.watts} W now` : ""]
    .filter(Boolean).join(" · ");
  return (
    <PanelSection title="Battery">
      <PanelSectionRow>
        <Field label={`${b.percent ?? "?"}% · ${batteryLine(b)}`} description={`At this power and load. ${how}`} />
      </PanelSectionRow>
    </PanelSection>
  );
}

// ------------------------------------------------------------ Quick Access tab
function Content() {
  const { items } = useHubState();
  const dev = useDevice();
  const running = items.filter(isRunning);
  const recent = items.filter((i) => !isRunning(i));

  return (
    <>
      <QuickSettings dev={dev} />
      <PanelSection title="In progress">
        {running.length === 0 && (
          <PanelSectionRow>
            <Field label="Nothing running" description="Downloads, copies and installs show here." />
          </PanelSectionRow>
        )}
        {running.map((i) => (
          <PanelSectionRow key={i.id}>
            <ProgressBarWithInfo
              label={i.title || i.app}
              description={[i.body, i.detail].filter(Boolean).join(" · ")}
              nProgress={i.percent ?? 0}
              indeterminate={i.percent == null}
              sOperationText={i.state === "paused" ? "Paused" : i.percent != null ? `${i.percent}%` : "Working…"}
            />
            {i.cancellable && (
              <ButtonItem layout="below" onClick={() => cancel(i.id)}>
                Cancel
              </ButtonItem>
            )}
          </PanelSectionRow>
        ))}
      </PanelSection>

      <PanelSection title="Notifications">
        {recent.length === 0 && (
          <PanelSectionRow>
            <Field label="No notifications" />
          </PanelSectionRow>
        )}
        {recent.map((i) => (
          <PanelSectionRow key={i.id}>
            <ButtonItem
              layout="inline"
              label={i.title || i.app}
              description={i.state === "failed" ? `Failed${i.body ? ": " + i.body : ""}` : i.body}
              onClick={() => dismiss(i.id)}
            >
              Dismiss
            </ButtonItem>
          </PanelSectionRow>
        ))}
        {recent.length > 0 && (
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={() => clearAll()}>
              Clear all
            </ButtonItem>
          </PanelSectionRow>
        )}
      </PanelSection>
      <BatterySection dev={dev} />
    </>
  );
}

export default definePlugin(() => {
  let firstLoad = true;
  const onState = (s: HubState) => {
    toastChanges(s, firstLoad);
    firstLoad = false;
    publish(s);
  };
  const listener = addEventListener<[HubState]>("gosaab_state", onState);
  getState().then(onState).catch(() => undefined);

  return {
    name: "Gill(OS)",
    titleView: <div className={staticClasses.Title}>Gill(OS)</div>,
    content: <Content />,
    icon: <FaBell />,
    onDismount() {
      removeEventListener("gosaab_state", listener);
    },
  };
});
