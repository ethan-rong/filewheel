<div align="center">

<img src="docs/mark.svg" width="96" alt="FileWheel" />

# FileWheel

### A new format. A small gesture.

A translucent conversion wheel, right where your files are.

**macOS · Adaptive appearance · Original files preserved**

</div>

---

## The idea

Hover over a file, choose a format from a radial picker, and find the converted copy beside the original. The wheel shows relevant choices for images, documents, PDFs, audio, and video.

Light frosted material in light mode. Smoked material in dark mode. Clear, opaque labels in both. Inspired by [Filee's radial interaction](https://filee.sh/), with an original native macOS design.

## Project status

**Design stage — no working release yet.** The interaction and visual direction are defined. The setup model is being selected: Finder hover requires a local background helper and Accessibility permission; a browser-only version would require choosing or dropping files inside the browser.

Read the [design notes](docs/DESIGN.md).

## Principles

- Keep the original. Write a new file, never silently overwrite one.
- Convert the contents, not just the extension.
- Show only meaningful formats for the selected file.
- Keep files local.
- Keep the interface small.

## License

MIT. FileWheel is an independent project and is not affiliated with Filee.
