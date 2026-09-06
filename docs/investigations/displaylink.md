# DisplayLink (docks)

Docks that drive external displays over USB need Synaptics' driver, and there is
no cask for it — download DisplayLink Manager by hand:
<https://www.synaptics.com/products/displaylink-graphics/downloads/macos>

It then needs **Screen & System Audio Recording** permission (the pane older
notes still call _Screen Recording_), granted in **System Settings → Privacy &
Security** — it captures the desktop to push those pixels over USB. Without it
the external screens stay black.
