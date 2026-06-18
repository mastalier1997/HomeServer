# 🚀 Personal Home Cloud & Infrastructure

I maintain a 24/7 dedicated home server based on Debian, designed to manage my data independently and host local AI services, media streaming, and a fully automated media acquisition pipeline.

## 🛠 Hardware & OS

- **CPU:** Intel Core i3-8100 (utilizing Intel QuickSync for efficient hardware transcoding)
- **OS:** Debian GNU/Linux
- **Management:** CasaOS Dashboard
- **Storage:** Dedicated data drive mounted at `/mnt/Storage1` (single filesystem — important for hardlinking, see below)
- **Connectivity:** Secured via Tailscale Mesh-VPN for encrypted remote access without open ports

## 📦 Services & Applications

### Core
- **OpenClaw AI** — locally hosted AI assistant for private, on-premise intelligence
- **Jellyfin** — personal media streaming server for high-definition movies and series
- **Immich** — high-performance, self-hosted photo and video backup solution
- **Docker** — all services containerized for stability, easy updates, and isolation

### Media Automation Stack (the "*arr" stack)
A self-managing pipeline that searches, downloads, organizes, and serves media with no manual file handling.

| Service | Role | Port |
|---------|------|------|
| **qBittorrent** | Download client (torrents) | `8180` → 8080 |
| **Prowlarr** | Indexer/tracker manager — syncs indexers to Radarr & Sonarr | `9696` |
| **Radarr** | Movie management & automation | `7878` |
| **Sonarr** | TV & anime management & automation | `8989` |
| **Jellyseerr** | Request UI — browse and request, feeds Radarr/Sonarr | `5055` |
| **Jellyfin** | Media streaming / playback | `8096` |

**The flow:** Request in Jellyseerr → Radarr/Sonarr search via Prowlarr's indexers → download in qBittorrent → **hardlinked** into the Jellyfin library folders → appears in Jellyfin automatically.

---

## 🗂 Storage Layout

Everything the stack touches lives under a single filesystem (`/mnt/Storage1`) so files can be **hardlinked** rather than copied. Hardlinking means a downloaded file exists in both the torrents folder (for seeding) and the media library (for Jellyfin) while only taking up disk space **once**.

```
/mnt/Storage1/
├── Jellfin/                  ← media library (note: folder name is "Jellfin")
│   ├── movies/               ← Radarr root folder
│   ├── series/               ← Sonarr root folder
│   └── anime/                ← Sonarr anime root folder (optional separate library)
├── torrents/                 ← qBittorrent completed downloads
│   └── incomplete/           ← qBittorrent in-progress downloads
├── appdata/                  ← per-app config (some apps use CasaOS /DATA/AppData)
└── lost+found/
```

### ⚠️ The single most important rule: one shared mount
Every app that touches media (qBittorrent, Radarr, Sonarr) mounts the **parent** directory as one volume, **not** individual subfolders:

```
/mnt/Storage1  →  /data
```

So inside the containers:
- qBittorrent save path: `/data/torrents` (incomplete: `/data/torrents/incomplete`)
- Radarr root folder: `/data/Jellfin/movies`, sees downloads at `/data/torrents`
- Sonarr root folders: `/data/Jellfin/series` and `/data/Jellfin/anime`

If you instead mount `/movies` and `/downloads` as **separate** volumes (CasaOS's default), the containers see two different filesystems and silently **copy** files instead of hardlinking — slow and doubles storage. Always collapse to the single `/data` mount.

Jellyfin keeps its own existing mount (e.g. `/mnt/Storage1/Jellfin → /Jellyfin`); it doesn't need `/data`.

---

## 🔧 Setup Guide

> All containers run with **PUID/PGID = 1000** (user `jan`), **TZ = Europe/Vienna**, **UMASK = 002**, on **bridge** networking. Server LAN IP: `192.168.0.240`.

### 1. qBittorrent (download client — set up first)
- **Image:** `ghcr.io/hotio/qbittorrent` (or `linuxserver/qbittorrent`)
- **Port:** host `8180` → container `8080`
- **Volumes:**
  - `/mnt/Storage1/appdata/qbittorrent` → `/config`
  - `/mnt/Storage1` → `/data`
- **First login:** get the temporary admin password from the logs:
  ```
  sudo docker logs qbittorrent 2>&1 | grep -i password
  ```
  Log in at `http://192.168.0.240:8180` (user `admin`), then **Settings → Web UI → Authentication** to set a real password.
- **Settings → Downloads:**
  - Default Save Path: `/data/torrents`
  - Keep incomplete torrents in: `/data/torrents/incomplete`

### 2. Prowlarr (indexer manager)
- **Image:** `linuxserver/prowlarr` (or hotio)
- **Port:** `9696` → `9696`
- **Volume:** `/config` only (no media mount needed)
- On first load, create a login.
- **Settings → Download Clients → + → qBittorrent:** host `192.168.0.240`, port `8180`, user `admin` + password → Test → Save
- **Indexers → + Add Indexer:** add your chosen indexers (e.g. public ones; **Nyaa** for anime). Test each.

### 3. Radarr (movies)
- **Image:** `linuxserver/radarr`
- **Port:** `7878` → `7878`
- **Volumes:** `/config` + **single** `/mnt/Storage1 → /data` (delete CasaOS's default `/movies` and `/downloads` rows)
- **Settings → Download Clients → + → qBittorrent** (host `192.168.0.240`, port `8180`) → Test → Save
- **Settings → Media Management → Root Folders → +** → `/data/Jellfin/movies` (should show free space)
- **Link from Prowlarr:** Prowlarr → Settings → Apps → + → Radarr → Radarr server `http://192.168.0.240:7878` + Radarr API key (Radarr → Settings → General) → Test → Save. Indexers auto-sync into Radarr.

### 4. Sonarr (TV & anime)
- **Image:** `linuxserver/sonarr`
- **Port:** `8989` → `8989`
- **Volumes:** `/config` + **single** `/mnt/Storage1 → /data` (delete default `/tv` and `/downloads` rows)
- Same three wiring steps as Radarr:
  - Download client → qBittorrent
  - Root folders → `/data/Jellfin/series` (and `/data/Jellfin/anime` if using a separate anime library)
  - Link from Prowlarr → Settings → Apps → + → Sonarr (`http://192.168.0.240:8989` + Sonarr API key)

### 5. Jellyseerr (request UI)
- **Image:** `fallenbagel/jellyseerr`
- **Port:** `5055` → `5055`
- **Volume:** `/app/config` only (no media mount; doesn't touch files; no PUID/PGID needed)
- Open `http://192.168.0.240:5055`, run the wizard:
  1. **Sign in with Jellyfin:** URL `http://192.168.0.240:8096`, Jellyfin admin account
  2. **Configure libraries:** select Movies / Series (/ Anime)
  3. **Settings → Services → Add Radarr:** host `192.168.0.240`, port `7878`, API key → Test → set Quality Profile + Root Folder `/data/Jellfin/movies` → Default Server → Save
  4. **Add Sonarr:** host `192.168.0.240`, port `8989`, API key → Test → set Quality Profile + Root Folder `/data/Jellfin/series`, Anime Root Folder as desired → Default Server → Save

---

## 🎬 Adding a Separate Anime Library (optional)

Anime benefits from Sonarr's "anime" series type (handles absolute episode numbering and scene release groups). To give it its own library:

1. **Create the folder:**
   ```
   sudo mkdir -p /mnt/Storage1/Jellfin/anime
   sudo chown 1000:1000 /mnt/Storage1/Jellfin/anime
   sudo chmod 777 /mnt/Storage1/Jellfin/anime
   ```
2. **Add to Sonarr:** Settings → Media Management → Root Folders → + → `/data/Jellfin/anime`
3. **Add to Jellyfin:** Dashboard → Libraries → Add Media Library → type **Shows**, name "Anime", folder = the path *Jellyfin's container* sees (e.g. `/Jellyfin/anime`). Confirm the container path with:
   ```
   sudo docker inspect jellyfin --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
   ```
4. **Point Jellyseerr at it:** Settings → Services → Sonarr → Anime Root Folder → `/data/Jellfin/anime` (re-Test to refresh the dropdown).

### Auto-downloading weekly-airing anime
- Add/request the show with **anime series type** and monitoring set to **Future Episodes** (or "All Episodes" for current season + future).
- **RSS Sync** (runs every ~15–30 min by default) automatically catches each new episode from your indexers and sends it to qBittorrent — no manual action needed.
- Make sure an anime-carrying indexer (e.g. **Nyaa**) is active in Prowlarr.
- Optional: **Settings → Profiles → Delay Profiles** — add a short delay so Sonarr waits for a preferred release group rather than grabbing the first one.

---

## 🔐 Permissions Note (important gotcha)

All stack apps run as **UID/GID 1000** (`jan`). Any folder they need to **write** to must be owned by `1000:1000` (or be world-writable). The drive root and new folders often default to `root:root`, which causes qBittorrent "Errored" (disk write) failures and Radarr/Sonarr import failures.

Fix for any new write target:
```
sudo chown -R 1000:1000 /mnt/Storage1/<folder>
```
The media folders (`movies`, `series`) are currently `chmod 777`, so writes there already succeed.

---

## 🛡 To-Do / Future Hardening

- [ ] **VPN for the download client** — route qBittorrent through a **gluetun** container (recommended in AT/DACH due to *Abmahnung* enforcement on public torrents). Self-contained change; doesn't disturb the rest of the stack. Needs a P2P-friendly provider with port forwarding (e.g. AirVPN, Proton VPN).
- [ ] **Bazarr** — automatic subtitle downloading for movies and series.
- [ ] Tighten the `777` permissions on media folders to something stricter once user/group ownership is fully aligned.
- [ ] Consider anime metadata plugins (AniDB/AniList) in Jellyfin for better matching.
