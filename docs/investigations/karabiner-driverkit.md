# Karabiner DriverKit VirtualHIDDevice Version Mismatch

kanata, installed by Ansible later, drives the keyboard through this virtual HID
driver. Take **package version 6.2.0** specifically — the newer driver bundled with full Karabiner-Elements breaks kanata.

Download that release's `.pkg` from
<https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases> and
install it. Installing only places the Manager app; the driver stays dormant
until you activate it, which is what triggers the approval prompt in **System
Settings → Privacy & Security**:

```bash
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

Expect two version numbers that never match. The pqrs _package_ is 6.2.0, which
only the Manager app's `Info.plist` reports; the _extension_ it registers calls
itself 1.8.0, and that is the only number `systemextensionsctl` will ever show:

```bash
plutil -p /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/Info.plist | grep ShortVersion
# "CFBundleShortVersionString" => "6.2.0"

systemextensionsctl list | grep Karabiner
# ...VirtualHIDDevice (1.8.0/1.8.0) ... [activated enabled]
```

The `kanata` role checks both and stops if the extension is not active.
