# DiscoPilot UAVPAL Mod

DiscoPilot is a UAVPAL-based softmod for the Parrot Disco and Skycontroller 2. It keeps the original UAVPAL ZeroTier workflow while adding support for newer USB Ethernet modems.

Warning:

- This is a work-in-progress proof of concept, not a polished release.
- Test on the bench before flight.
- Be prepared to uninstall, reboot, and fall back to stock Wi-Fi/SC2 behavior.
- Use at your own risk.

Goals:

- Support more LTE modem paths without making startup/reconnect behavior more fragile.
- Keep Wi-Fi mode behavior intact.
- Keep plane scripts BusyBox-compatible and low overhead.
- Keep ZeroTier, route setup, telemetry, and maintenance changes easy to review and roll back.
- Remove external notification/tracking service dependencies.

Removed upstream UAVPAL services:

- Pushbullet support has been removed.
- Glympse support has been removed.
- Status is exposed locally through the mod's telemetry endpoint instead of being pushed to third-party services.
- Maintenance actions are exposed locally through the mod's maintenance endpoint.
- These local endpoints are intended for trusted local/ZeroTier use, not public internet exposure.

Telemetry endpoint:

- The local telemetry endpoint was added to support the DiscoPilot controller app.
- It returns plain JSON and can be read by any client that can reach the Disco over local Wi-Fi or ZeroTier.
- Endpoint: `http://<disco-ip>:18080/telemetry.json`
- Users who do not need app telemetry can ignore it; it is not required for the modem connection itself.

Maintenance endpoint:

- The local maintenance endpoint is used for simple actions such as enabling telnet or requesting shutdown/reboot.
- Endpoint: `http://<disco-ip>:18080/cgi-bin/maintenance`
- Use it only from trusted local Wi-Fi or ZeroTier clients.

Layout:

- `disco/uavpal/` is the canonical plane-side package source.
- `skycontroller2/uavpal/` is the canonical Skycontroller 2 package source.

Plane package scripts:

- `disco/uavpal/discopilot_disco_install.sh` is the tested fresh plane install script.
- `disco/uavpal/discopilot_disco_uninstall.sh` is the tested plane uninstall script.
- Both are run from the transferred repo folder on the Disco, for example `/data/ftp/internal_000/discopilot/disco/uavpal`.

Fresh plane install:

1. Transfer the folder `discopilot/` to the Disco's internal storage so it appears as `/data/ftp/internal_000/discopilot`.
2. Open a shell on the Disco.
3. Run each command one at a time:

```sh
cd /data/ftp/internal_000/discopilot/disco/uavpal
```

```sh
sh -n discopilot_disco_install.sh
```

```sh
sh discopilot_disco_install.sh
```

4. Reboot the Disco or reconnect the modem to start the mod.
5. Authorize the new Disco member in ZeroTier Central if this is a fresh ZeroTier identity.

Plane uninstall:

1. Transfer the folder `discopilot/` to the Disco's internal storage if it is not already there.
2. Open a shell on the Disco.
3. Run each command one at a time:

```sh
cd /data/ftp/internal_000/discopilot/disco/uavpal
```

```sh
sh -n discopilot_disco_uninstall.sh
```

```sh
sh discopilot_disco_uninstall.sh
```

4. Reboot the Disco before normal use.

Deployment paths are unchanged:

- Plane: `/data/ftp/uavpal`
- Skycontroller 2: `/data/lib/ftp/uavpal`

Skycontroller 2 install:

1. Install the plane side first so `/data/ftp/uavpal/bin/adb` exists on the Disco.
2. Keep the Skycontroller 2 connected normally to the Disco.
3. Open a shell on the Disco.
4. Run each command one at a time:

```sh
cd /data/ftp/internal_000/discopilot/skycontroller2
```

```sh
sh -n discopilot_sc2_install.sh
```

```sh
sh discopilot_sc2_install.sh
```

5. Reboot the Skycontroller 2 before testing LTE mode.

Skycontroller 2 uninstall:

1. Keep the Skycontroller 2 connected normally to the Disco.
2. Open a shell on the Disco.
3. Run each command one at a time:

```sh
cd /data/ftp/internal_000/discopilot/skycontroller2
```

```sh
sh -n discopilot_sc2_uninstall.sh
```

```sh
sh discopilot_sc2_uninstall.sh
```

4. Reboot the Skycontroller 2 before normal use.

The SC2 scripts detect the local Skycontroller 2 IP from the Disco's active `9988` UDP session and connect to local ADB on port `9050`.

Do not rename deployed paths unless that is planned as a separate high-risk migration.

Modem compatibility:

- Original UAVPAL Huawei modem paths are still supported.
- Generic USB Ethernet modems are supported when the modem exposes a normal Linux network interface and provides DHCP.
- Tested generic Ethernet modems:
  - Inseego USB8L
  - Quectel RM520N in ECM mode
- Signal reporting is best-effort. Some generic Ethernet modems expose signal through an admin page/API; others may connect normally while showing unknown signal.
- QMI, MBIM, PPP-only, and unsupported USB network modes are not handled by the generic Ethernet path.

USB8L notes:

- The Inseego USB8L works well as a generic Ethernet modem.
- IP Passthrough/IPPT is recommended when available.
- Configure IPPT and carrier settings in the modem web UI before connecting it to the Disco.

Quectel ECM notes:

- Quectel RM520N/RM502-style modems should be placed in ECM mode before use.
- The expected Quectel ECM mode is:

```sh
AT+QCFG="usbnet",1
```

- After changing Quectel USB mode, reset the modem:

```sh
AT+CFUN=1,1
```

- Run AT mode changes only on the bench, not during flight.
- Other Quectel ECM modems may work if they expose a supported Ethernet interface and their USB ID is included in the modem detection list.

APN and carrier setup:

- Set your carrier APN in:

```text
disco/uavpal/conf/apn
```

- The APN is carrier-specific. Use the APN provided by your SIM or carrier.
- Some generic Ethernet modems manage APN internally. In that case, configure the APN in the modem web UI or modem AT settings before using it with the Disco.

Optional Quectel bench check:

- `disco/uavpal/bin/uavpal_quectel_ecm.sh` is a manual bench tool for the Quectel RM520N in ECM mode.
- `check` is read-only and prints USB mode, APN/CID state, QMAP state, carrier aggregation, temperatures, route, and ZeroTier state.
- `provision` is bench-only and points QMAP rule 0 at the configured `conf/apn` CID when that APN exists. It does not force bands, lock RAT, or change SIM credentials.

Run on the Disco after the installed package has been updated:

```sh
/data/ftp/uavpal/bin/uavpal_quectel_ecm.sh check
```

Only if the check shows QMAP is not using the configured APN, run:

```sh
/data/ftp/uavpal/bin/uavpal_quectel_ecm.sh provision
```

Then reboot the Disco or reset/replug the modem before flight testing.
