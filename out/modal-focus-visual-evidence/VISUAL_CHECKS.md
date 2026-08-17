# Modal Focus Visual v1 — X11/Vulkan Screenshot Check

The three captured frames were visually reviewed after the fixed X11 input sequence ran against `material-overlay-showcase.scene.json` with the Vulkan backend.

| Frame | Fixed input state | Visual result |
|---|---|---|
| `01-modal-open-initial-ring.png` | Modal opened; initial fixed slot `3` (`deployment-confirm`) | A blue, rounded, hollow focus ring is visible around **Deploy**. It is above the dialog surface and does not cover the button label. |
| `02-modal-tab-second-ring.png` | One `Tab`; fixed slot transition `3 → 2` | The outline has moved to **Cancel**. The prior Deploy outline is absent, confirming the old-alpha `0` / new-alpha `1` patch pair. |
| `03-modal-closed-rings-hidden.png` | `Escape`; overlay close path | The dialog is absent and no focus outline remains in the application frame. |

`x11-vulkan.log` records the same fixed execution: five resident outline quads, local tile mask `0x1`, one alpha patch on open, two patches on Tab, and a five-ring clear on close.
