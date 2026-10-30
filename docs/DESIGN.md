# FileWheel · Design notes

## A new format. A small gesture.

FileWheel brings the formats to the file. The reference is [Filee's radial picker](https://filee.sh/); the interface, implementation, and visual identity are original.

The wheel appears only after an intentional hover. A filename stays visible in the center so the user always knows what will be converted. Selecting a format creates a sibling file. Existing files are never replaced.

## Material, not opacity

Use native backdrop material for the wheel sectors, with a fine border separating each target from the desktop. Do not lower the opacity of the whole interface: labels and icons remain fully opaque. Light mode uses pale frosted surfaces and ink labels; dark mode uses smoked surfaces and near-white labels. Respect the system appearance and Reduce Transparency. Selection uses a solid violet surface and white type in both modes.

| Token | Light | Dark |
| --- | --- | --- |
| Label | `#181820` | `#F5F3FF` |
| Supporting label | `#54515E` | `#C4BFCE` |
| Selection | `#6446C7` | `#6446C7` |
| Surface | Native light material | Native dark material |
| Typography | SF Pro, system size and weight | SF Pro, system size and weight |
| Iconography | SF Symbols | SF Symbols |

## Interaction

- A short dwell opens the wheel; moving past a file does not.
- The center identifies the file and its category.
- Formats occupy evenly spaced sectors, with generous click targets.
- Hover previews the selection; click or Return converts.
- Arrow keys, Tab, and the mouse wheel move between formats.
- Escape and clicking away dismiss the picker.
- Conversion state replaces the picker until completion or cancellation.
- A completed conversion offers a direct reveal in Finder.

Only supported conversions appear. Missing conversion engines are explained clearly. Errors stay visible, and the original file stays untouched.

## Scope

Common images, documents, PDF pages, audio, and video. No upload, account, subscription, editor, or decorative dashboard. Finder integration necessarily requires a local process and the user's Accessibility permission.
