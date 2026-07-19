# AirPods-Studio

Turn your Raspberry Pi into a Bluetooth audio sink and Spotify Connect speaker (via librespot).  
Runs automatically at boot.

## Quick install

1. **Save the script**  
   Put `airpods-studio.sh` in `/root/airpods-studio.sh` and make it executable:
   ```bash
   sudo chmod +x /root/airpods-studio.sh
   ```

2. **Create systemd service**  
   Write this to `/etc/systemd/system/airpods-studio.service`:
   ```ini
   [Unit]
   Description=AirPods-Studio
   After=network.target bluetooth.service
   Requires=bluetooth.service

   [Service]
   Type=simple
   ExecStart=/root/airpods-studio.sh
   Restart=on-failure
   RestartSec=5
   User=root
   Environment=PULSE_RUNTIME_PATH=/var/run/pulse

   [Install]
   WantedBy=multi-user.target
   ```

3. **Enable and start**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now airpods-studio
   ```

4. **Check it’s running**
   ```bash
   sudo journalctl -u airpods-studio -f
   ```

Now pair your phone to **AirPods-Studio** (no PIN) and play audio.  
Spotify Connect will also appear automatically.

## Requirements

- librespot installed (run `sudo cargo install librespot` if missing)
- The script installs all other dependencies on first run
