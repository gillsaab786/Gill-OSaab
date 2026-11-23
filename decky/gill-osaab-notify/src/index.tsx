import {
  ButtonItem,
  Field,
  PanelSection,
  PanelSectionRow,
  ProgressBarWithInfo,
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

const getState = callable<[], HubState>("get_state");
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

// ------------------------------------------------------------ Quick Access tab
function Content() {
  const { items } = useHubState();
  const running = items.filter(isRunning);
  const recent = items.filter((i) => !isRunning(i));

  return (
    <>
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
    name: "Gill-OSaab Notifications",
    titleView: <div className={staticClasses.Title}>Notifications</div>,
    content: <Content />,
    icon: <FaBell />,
    onDismount() {
      removeEventListener("gosaab_state", listener);
    },
  };
});
