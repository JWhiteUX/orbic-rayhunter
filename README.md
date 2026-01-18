# orbic-rayhunter

A companion tool for [Rayhunter](https://github.com/EFForg/rayhunter) that enables local push notifications without cellular service.

> **Note:** This is a standalone utility, not a fork. Rayhunter must be installed separately on your Orbic device. See the [official Rayhunter installation guide](https://github.com/EFForg/rayhunter#installation).

## The Problem

Rayhunter runs on an Orbic mobile hotspot and can send push notifications via [ntfy](https://ntfy.sh) when it detects potential IMSI catchers (cell site simulators). However, without a SIM card, the Orbic has no internet access and can't reach external ntfy servers.

## The Solution

```
┌─────────────┐     USB      ┌─────────────┐      LAN       ┌─────────────┐
│   Orbic     │─────────────▶│  Linux Host │───────────────▶│   Phone     │
│ (Rayhunter) │  Tethering   │ (ntfy srv)  │   (Wi-Fi/Eth)  │ (ntfy app)  │
└─────────────┘              └─────────────┘                └─────────────┘
```

This script runs a local ntfy server on any Linux host (Raspberry Pi, laptop, etc.) connected to the Orbic via USB. The Orbic sends notifications to the local server, and your phone subscribes to the same topic over your LAN.

## What This Tool Does

- Manages a local ntfy server that the Orbic can reach via USB tethering
- Auto-detects USB tethering interface and network configuration
- Provides SSH tunnel commands for remote access to Rayhunter UI
- Displays configuration URLs for both Rayhunter and your phone's ntfy app

## What This Tool Does NOT Do

- Install or modify Rayhunter (you must install it separately)
- Require internet access on the Orbic
- Replace the public ntfy.sh service (it runs locally)

## Requirements

- **Orbic mobile hotspot with Rayhunter already installed** ([install guide](https://github.com/EFForg/rayhunter#installation))
- Linux host with USB port (Raspberry Pi, laptop, server, etc.)
- [ntfy](https://github.com/binwiederhier/ntfy/releases) binary installed on the Linux host
- USB cable
- ntfy app on your phone ([iOS](https://apps.apple.com/app/ntfy/id1625396347) / [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy))

## Installation

### Install This Tool

```bash
# Download
curl -LO https://raw.githubusercontent.com/JWhiteUX/orbic-rayhunter/main/orbic-rayhunter.sh
chmod +x orbic-rayhunter.sh

# Install to PATH
sudo ./orbic-rayhunter.sh install
```

### Install ntfy (on your Linux host)

Download the appropriate binary from [ntfy releases](https://github.com/binwiederhier/ntfy/releases):

```bash
# Example for ARM64 (Raspberry Pi 4)
curl -LO https://github.com/binwiederhier/ntfy/releases/download/v2.11.0/ntfy_2.11.0_linux_arm64.tar.gz
tar xzf ntfy_2.11.0_linux_arm64.tar.gz
sudo mv ntfy_2.11.0_linux_arm64/ntfy /usr/local/bin/

# Example for x86_64 (most laptops/desktops)
curl -LO https://github.com/binwiederhier/ntfy/releases/download/v2.11.0/ntfy_2.11.0_linux_amd64.tar.gz
tar xzf ntfy_2.11.0_linux_amd64.tar.gz
sudo mv ntfy_2.11.0_linux_amd64/ntfy /usr/local/bin/
```

## Usage

```bash
./orbic-rayhunter.sh start      # Start ntfy server, show config URLs
./orbic-rayhunter.sh stop       # Stop ntfy server
./orbic-rayhunter.sh status     # Show component status
./orbic-rayhunter.sh test       # Send test notification
./orbic-rayhunter.sh logs       # Tail ntfy server logs
./orbic-rayhunter.sh tunnel     # Show SSH tunnel commands for remote access
./orbic-rayhunter.sh --help     # Show help
```

## Quick Start

1. **Connect Orbic to your Linux host via USB**

2. **Enable USB tethering on the Orbic**
   - Settings → Network & Internet → Hotspot & Tethering → USB Tethering

3. **Start the bridge**
   ```bash
   ./orbic-rayhunter.sh start
   ```
   
   Output:
   ```
   === Orbic Rayhunter Setup ===
   
   USB interface: usb0 (192.168.1.113)
   Orbic reachable: 192.168.1.1
   Rayhunter responding: http://192.168.1.1:8080
   ntfy started (PID: 12345)
   
   === Configuration ===
   
   Rayhunter ntfy URL:
     http://192.168.1.113:8080/rayhunter
   
   Phone subscription URL:
     http://192.168.3.238:8080/rayhunter
   ```

4. **Configure Rayhunter** (see [Remote Access](#remote-access) below)

5. **Subscribe on your phone**
   - Open ntfy app
   - Add subscription with the "Phone subscription URL"

6. **Test**
   ```bash
   ./orbic-rayhunter.sh test
   ```

## Remote Access

The Orbic's web interfaces (Rayhunter UI and OEM Admin) are only directly accessible from the host machine. To access them from another computer on your network (e.g., your laptop), use SSH port forwarding.

### Get Tunnel Commands

```bash
./orbic-rayhunter.sh tunnel
```

Output:
```
=== SSH Tunnel Commands ===

Run one of these commands from another computer on your network
to access the Orbic web interfaces through this host.

Rayhunter UI only:
  ssh -L 8080:192.168.1.1:8080 user@192.168.3.238
  Then open: http://localhost:8080

Orbic OEM Admin only:
  ssh -L 8081:192.168.1.1:80 user@192.168.3.238
  Then open: http://localhost:8081

Both interfaces:
  ssh -L 8080:192.168.1.1:8080 -L 8081:192.168.1.1:80 user@192.168.3.238
  Then open:
    Rayhunter:   http://localhost:8080
    OEM Admin:   http://localhost:8081

Background tunnel (add -fN):
  ssh -fN -L 8080:192.168.1.1:8080 -L 8081:192.168.1.1:80 user@192.168.3.238
```

### Example: Access from MacBook

1. On your Linux host (e.g., Raspberry Pi), run `./orbic-rayhunter.sh tunnel` to get the SSH command

2. On your MacBook, open Terminal and run:
   ```bash
   ssh -L 8080:192.168.1.1:8080 -L 8081:192.168.1.1:80 user@<HOST_IP>
   ```

3. Open your browser:
   - **Rayhunter UI**: http://localhost:8080
   - **Orbic OEM Admin**: http://localhost:8081

4. In Rayhunter UI, paste the ntfy URL from `./orbic-rayhunter.sh start` output

### Background Tunnel

To run the tunnel in the background (doesn't require keeping terminal open):

```bash
ssh -fN -L 8080:192.168.1.1:8080 -L 8081:192.168.1.1:80 user@<HOST_IP>
```

To kill a background tunnel:
```bash
pkill -f "ssh -fN.*8080:192.168.1.1"
```

## Configuration

Configuration via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ORBIC_NTFY_PORT` | `8080` | Port for ntfy server |
| `ORBIC_NTFY_TOPIC` | `rayhunter` | Topic name for notifications |
| `ORBIC_GATEWAY` | `192.168.1.1` | Orbic gateway IP |
| `ORBIC_RAYHUNTER_PORT` | `8080` | Rayhunter web UI port |
| `ORBIC_ADMIN_PORT` | `80` | Orbic OEM admin port |
| `ORBIC_SSH_USER` | current user | SSH username for tunnel command |

Example with custom topic:
```bash
ORBIC_NTFY_TOPIC=my-alerts ./orbic-rayhunter.sh start
```

## Network Diagram

```
                                    Your Local Network
                                    ==================
                                    
┌─────────────────┐                                      ┌─────────────────┐
│     Orbic       │                                      │     Phone       │
│   Hotspot       │                                      │   (ntfy app)    │
│                 │                                      │                 │
│ Rayhunter:8080  │                                      │ Subscribes to:  │
│ OEM Admin:80    │                                      │ HOST_IP:8080    │
└────────┬────────┘                                      └────────▲────────┘
         │ USB Tether                                             │
         │ 192.168.1.x                                            │ Wi-Fi/LAN
         │                                                        │
         ▼                                                        │
┌─────────────────┐          SSH Tunnel           ┌───────────────┴─┐
│   Linux Host    │◀─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│    Laptop       │
│ (Pi, server,    │       (for UI access)         │   (optional)    │
│  laptop, etc.)  │                               │                 │
│                 │                               │ localhost:8080  │
│ usb0: 192.168.1.x                               │ localhost:8081  │
│ eth0: LAN IP    │                               └─────────────────┘
│ ntfy server     │
└─────────────────┘

Data flow:
─────────►  USB tethering / direct connection
─ ─ ─ ─ ►  SSH tunnel (optional, for remote UI access)
```

## Troubleshooting

### USB interface not found

- Ensure Orbic is connected and USB tethering is enabled
- Check available interfaces: `ip link show`
- The interface is typically named `usb0`, `enp0s*u*`, or similar

### Can't reach Orbic

- Verify USB tethering is enabled on the Orbic
- Check if the USB interface has an IP: `ip addr show usb0`
- Try requesting DHCP: `sudo dhclient usb0`

### Phone not receiving notifications

- Ensure phone is on the same network as the host's LAN interface
- Check firewall rules: `sudo iptables -L`
- Test locally: `curl -d "test" http://localhost:8080/rayhunter`

### ntfy won't start

- Check if port is in use: `ss -tlnp | grep 8080`
- View logs: `./orbic-rayhunter.sh logs` or `cat /tmp/orbic-rayhunter-ntfy.log`
- Try a different port: `ORBIC_NTFY_PORT=9090 ./orbic-rayhunter.sh start`

### Can't access Rayhunter UI remotely

- Make sure SSH tunnel is running
- Verify the tunnel command uses the correct host IP
- Check that nothing else is using localhost:8080 on your laptop

## Files

| Path | Description |
|------|-------------|
| `/tmp/orbic-rayhunter-ntfy.pid` | ntfy process ID |
| `/tmp/orbic-rayhunter-ntfy.log` | ntfy server logs |

## Uninstall

```bash
./orbic-rayhunter.sh stop
sudo ./orbic-rayhunter.sh uninstall
```

## Related Projects

- [Rayhunter](https://github.com/EFForg/rayhunter) - IMSI catcher detection for Orbic hotspots (by EFF)
- [ntfy](https://github.com/binwiederhier/ntfy) - Simple pub-sub notification service

## Credits

- [Electronic Frontier Foundation (EFF)](https://www.eff.org/) for creating Rayhunter
- [Philipp C. Heckel](https://github.com/binwiederhier) for ntfy

## License

MIT
