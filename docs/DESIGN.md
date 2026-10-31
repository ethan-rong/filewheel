# FileWheel · Design notes

## A new format. A small gesture.

FileWheel brings the formats to the file. The reference is [Filee's radial picker](https://filee.sh/); the interface, implementation, and visual identity are original.

The compact 256-point wheel appears when the pointer reaches a supported file, with no intentional dwell. A filename stays visible in the center so the user always knows what will be converted. Clicking a format starts conversion immediately and creates a sibling file. Existing files are never replaced.

## Material, not opacity

Use native backdrop material for the wheel sectors, with a fine border separating each target from the desktop. Do not lower the opacity of the whole interface: labels and icons remain fully opaque. Light mode uses white frosted surfaces and black labels; dark mode uses black smoked surfaces and white labels. Respect the system appearance and Reduce Transparency. Selection inverts the foreground and background: black with white type in light mode, white with black type in dark mode. No chromatic accents.

| Token | Light | Dark |
| --- | --- | --- |
| Label | `#000000` | `#FFFFFF` |
| Supporting label | `#4D4D4D` | `#CCCCCC` |
| Selection | `#000000` | `#FFFFFF` |
| Surface | Native light material | Native dark material |
| Typography | SF Pro, system size and weight | SF Pro, system size and weight |
| Iconography | SF Symbols | SF Symbols |

## Interaction

- Pointer checks run every 50 ms and open the wheel without a dwell. Passing over a supported file can open it; Pause hovering disables this.
- The center identifies the file and its category.
- Formats occupy evenly spaced sectors, with generous click targets.
- Hover previews the selection; click or Return converts.
- Arrow keys, Tab, and the mouse wheel move between formats.
- Escape and clicking away dismiss the picker.
- Conversion state replaces the picker until completion or cancellation.
- The center expands during conversion, completion, or error so messages stay readable in the smaller panel.
- A completed conversion offers a direct reveal in Finder.

Only supported conversions appear. Missing conversion engines are explained clearly. Errors stay visible, and the original file stays untouched.

## Scope

Common images, documents, PDF pages, audio, and video. No upload, account, subscription, editor, or decorative dashboard. Finder integration necessarily requires a local process and the user's Accessibility permission.
