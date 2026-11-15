import { PanelSection, PanelSectionRow, ToggleField, Field, staticClasses } from "@decky/ui";
import { callable, definePlugin } from "@decky/api";
import { useEffect, useState } from "react";
import { FaComments } from "react-icons/fa";

type State = { on: boolean; states: string[]; url: string };
const getState = callable<[], State>("get_state");
const setOn = callable<[on: boolean], State>("set_on");

function Content() {
  const [state, setState] = useState<State | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    getState().then(setState);
  }, []);

  const toggle = async (on: boolean) => {
    setBusy(true);
    try {
      setState(await setOn(on));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PanelSection>
      <PanelSectionRow>
        <ToggleField
          label="WoW Chat"
          description={state ? (state.on ? "On: phone page and typing" : "Off") : "…"}
          checked={state?.on ?? false}
          disabled={busy || !state}
          onChange={toggle}
        />
      </PanelSectionRow>
      {state?.on && (
        <PanelSectionRow>
          <Field label="Phone" description={state.url} />
        </PanelSectionRow>
      )}
    </PanelSection>
  );
}

export default definePlugin(() => ({
  name: "WoW Chat",
  titleView: <div className={staticClasses.Title}>WoW Chat</div>,
  content: <Content />,
  icon: <FaComments />,
}));
