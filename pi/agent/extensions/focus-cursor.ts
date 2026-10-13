/**
 * Focus-aware cursor: hides both the visual cursor block (reverse-video
 * \x1b[7m) and the hardware cursor when pi's TUI loses window/pane focus.
 *
 * Enables terminal focus-reporting (DEC private mode 1004) so terminals
 * and tmux (with focus-events on) emit:
 *   Focus In  → CSI I  (\x1b[I)
 *   Focus Out → CSI O  (\x1b[O)
 *
 * Two mechanisms:
 *  1. Visual cursor block: FocusAwareEditor subclasses CustomEditor
 *     and strips \x1b[7m…\x1b[0m from rendered lines when unfocused.
 *  2. Hardware cursor: toggled via \x1b[?25h/\x1b[?25l on focus change.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { CustomEditor } from "@earendil-works/pi-coding-agent";

const FOCUS_IN = "\x1b[I";
const FOCUS_OUT = "\x1b[O";

const CURSOR_SHOW = "\x1b[?25h";
const CURSOR_HIDE = "\x1b[?25l";

const ENABLE_FOCUS_REPORTING = "\x1b[?1004h";
const DISABLE_FOCUS_REPORTING = "\x1b[?1004l";

/** Regex matching the editor's visual cursor block: \x1b[7mX\x1b[0m */
const CURSOR_BLOCK_RE = /\x1b\[7m(.)\x1b\[0m/g;

/**
 * CustomEditor subclass that strips the visual cursor block when
 * the terminal/pane is not focused.
 */
class FocusAwareEditor extends CustomEditor {
  private _appFocused = true;

  setAppFocused(value: boolean): void {
    if (this._appFocused === value) return;
    this._appFocused = value;
    this.invalidate();
    // Re-render needed — caller should call tui.requestRender()
  }

  render(width: number): string[] {
    const lines = super.render(width);
    if (this._appFocused) return lines;
    // Strip reverse-video cursor block, preserving the character
    return lines.map((line) => line.replace(CURSOR_BLOCK_RE, "$1"));
  }
}

export default function (pi: ExtensionAPI) {
  let hardwareCursorEnabled = false;
  let cleanupTerminalInput: (() => void) | undefined;
  let focusEditor: FocusAwareEditor | undefined;
  let tuiRef: any = undefined;

  pi.on("session_start", async (_event, ctx) => {
    hardwareCursorEnabled = process.env.PI_HARDWARE_CURSOR === "1";

    // Ask terminal to send focus events
    process.stdout.write(ENABLE_FOCUS_REPORTING);

    // Replace editor with focus-aware wrapper
    ctx.ui.setEditorComponent((tui, theme, keybindings) => {
      tuiRef = tui;
      focusEditor = new FocusAwareEditor(tui, theme, keybindings, {
        paddingX: 1,
        paddingY: 0,
      });
      return focusEditor;
    });

    cleanupTerminalInput = ctx.ui.onTerminalInput((data) => {
      if (data === FOCUS_IN) {
        if (hardwareCursorEnabled) {
          process.stdout.write(CURSOR_SHOW);
        }
        focusEditor?.setAppFocused(true);
        tuiRef?.requestRender();
        return { consume: true };
      }

      if (data === FOCUS_OUT) {
        process.stdout.write(CURSOR_HIDE);
        focusEditor?.setAppFocused(false);
        tuiRef?.requestRender();
        return { consume: true };
      }

      // Pass through all other input
      return;
    });
  });

  pi.on("session_shutdown", async () => {
    // Disable focus reporting so other terminal apps work normally
    process.stdout.write(DISABLE_FOCUS_REPORTING);

    // Ensure cursor is visible on exit
    process.stdout.write(CURSOR_SHOW);

    cleanupTerminalInput?.();
    cleanupTerminalInput = undefined;
    focusEditor = undefined;
    tuiRef = undefined;
  });
}
