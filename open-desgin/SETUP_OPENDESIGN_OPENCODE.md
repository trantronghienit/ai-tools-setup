# Hướng dẫn thiết lập Open Design + OpenCode CLI trong Docker

## Kiến trúc tổng quan

Hệ thống gồm 3 container:

| Container | Vai trò |
|-----------|---------|
| `open-design` | Daemon chính (API + web UI) |
| `open-design-proxy` | Reverse proxy, tự động thêm Bearer token vào mọi request `/api/*` |
| `open-design-tools` | Sidecar chứa `od` CLI + `opencode` CLI |

### Luồng hoạt động

```
Trình duyệt → open-design-proxy (thêm Bearer token) → open-design (daemon)
tools container → 127.0.0.1:7456 (loopback, không cần token)
```

---

## 1. Yêu cầu

- Docker Engine 24+
- Docker Compose v2

---

## 2. Clone dự án + copy file backup

```bash
# Bước 1: Clone repo gốc
git clone https://github.com/nexu-io/open-design.git
cd open-design/deploy

# Bước 2: Copy các file tùy chỉnh từ bản backup vào đây
# (docker-compose.yml, Dockerfile.daemon, Dockerfile.proxy,
#  Dockerfile.tools, proxy/proxy.mjs, setup.ps1, setup.sh)

# Bước 3: Chạy script setup (tự động làm các bước còn lại)
# Windows:
.\setup.ps1

# Linux/macOS:
chmod +x setup.sh && ./setup.sh
```

### Giải thích

Repo gốc chỉ chứa `Dockerfile` (build từ source) và `docker-compose.yml` cơ bản. Các file chúng ta thêm/sửa để có proxy + opencode + tools container là:

| File | Nguồn gốc |
|------|-----------|
| `docker-compose.yml` | **Sửa** từ bản gốc: thêm proxy service, bỏ ports của daemon, thêm tmpfs + HOME |
| `Dockerfile.daemon` | **Tạo mới**: kế thừa published image, copy opencode binary từ tools image |
| `Dockerfile.proxy` | **Tạo mới**: Node.js reverse proxy thêm Bearer token |
| `Dockerfile.tools` | **Sửa** từ bản gốc: đổi base image thành published image |
| `proxy/proxy.mjs` | **Tạo mới**: mã nguồn proxy |
| `setup.ps1` / `setup.sh` | **Tạo mới**: script tự động hóa |

> **Luồng đúng:** clone repo gốc → copy các file custom đã backup vào `deploy/` → chạy `setup.ps1` (hoặc `setup.sh`). Không chạy script trước khi copy file backup.

---

## 3. Chạy script setup

Script tự động làm tất cả: tạo `.env` + sinh token → build images → start services → verify.

### Lần đầu (clone mới)

```bash
# Windows (PowerShell)
cd open-design/deploy
.\setup.ps1

# Linux / macOS
cd open-design/deploy
chmod +x setup.sh && ./setup.sh
```

### Chạy lại (đã có thư mục, chỉ cần build lại)

```bash
# Windows
cd open-design/deploy
.\setup.ps1 -SkipClone

# Linux / macOS
cd open-design/deploy
./setup.sh
```

### Script làm gì?

| Bước | Mô tả |
|------|-------|
| 1. Kiểm tra | Docker + Docker Compose đã cài chưa |
| 2. Clone | `git clone` nếu chưa có thư mục (bỏ qua nếu dùng `-SkipClone`) |
| 3. `.env` | Copy từ `.env.example`, sinh `OD_API_TOKEN` ngẫu nhiên |
| 4. Build | `docker compose build` — build 3 images |
| 5. Start | `docker compose up -d` — khởi động container |
| 6. Chờ | Poll đến khi daemon healthy (tối đa 60s) |
| 7. Verify | Gọi `/api/health` và `/api/version` |
| 8. In kết quả | Web UI URL, token, hướng dẫn dùng OpenCode |

### Một số lưu ý

- Lần build đầu tiên có thể mất vài phút (tải base image ~400MB + opencode binary ~150MB). Các lần sau dùng cache.
- Nếu script thất bại ở bước build, kiểm tra kết nối mạng và Docker disk space.
- Nếu daemon không healthy sau 60s, chạy `docker compose logs open-design` để xem lỗi.
- Token được in ra màn hình sau khi chạy xong. Lưu lại nếu cần dùng sau.

---

## 4. Kiểm tra hoạt động (thủ công)

### API health

```bash
curl http://127.0.0.1:7456/api/health
# {"ok":true,"version":"0.8.1"}
```

### Daemon version

```bash
curl http://127.0.0.1:7456/api/version
# {"version":{"version":"0.8.1","channel":"development","packaged":false,...}}
```

### Agent detection (opencode)

```bash
curl -s -N -H "Accept: text/event-stream" --max-time 6 http://127.0.0.1:7456/api/agents?stream=1 | grep opencode
# "available":true,"version":"1.17.4","path":"/usr/local/bin/opencode-cli"
```

### Web UI

Mở trình duyệt: http://127.0.0.1:7456

Kiểm tra:
- Local CLI mode enabled (daemon live)
- OpenCode xuất hiện trong danh sách agent

---

## 5. Sử dụng OpenCode CLI

Chạy lệnh OpenCode bên trong tools container:

```bash
# Vào shell tools container
docker compose exec tools sh

# Chạy opencode
opencode run "giải thích cách hoạt động của Docker"

# Hoặc chạy trực tiếp
docker compose exec tools opencode run "viết một REST API đơn giản bằng Node.js"
```

Chạy lệnh `od` CLI:

```bash
docker compose exec tools od daemon status
docker compose exec tools od version
docker compose exec tools od plugin list
```

---

## 6. Sao lưu và triển khai trên máy khác

### File cần backup

```
deploy/
├── docker-compose.yml          # Đã sửa
├── Dockerfile.daemon           # File mới
├── Dockerfile.proxy            # File mới
├── Dockerfile.tools            # Đã sửa
├── proxy/
│   └── proxy.mjs               # File mới
├── setup.ps1                   # File mới
├── setup.sh                    # File mới
├── SETUP_OPENDESIGN_OPENCODE.md # File mới
├── .env                        (token riêng — backup riêng, không public)
└── .env.example
```

### Trên máy mới — đúng 3 bước

```bash
# Bước 1: Clone repo gốc
git clone https://github.com/nexu-io/open-design.git
cd open-design/deploy

# Bước 2: Copy các file custom từ bản backup vào thư mục deploy/
# (chép docker-compose.yml, Dockerfile.*, proxy/, setup.* từ backup vào đây)
cp /path/to/backup/docker-compose.yml .
cp /path/to/backup/Dockerfile.daemon .
cp /path/to/backup/Dockerfile.proxy .
cp /path/to/backup/Dockerfile.tools .
cp -r /path/to/backup/proxy/ .
cp /path/to/backup/setup.ps1 .
cp /path/to/backup/setup.sh .

# Bước 3: Chạy script setup (tự động tạo .env, sinh token, build, start)
.\setup.ps1
```

Hoặc nếu có file `.env` đã backup:

```bash
# Sau bước 2, copy luôn .env
cp /path/to/backup/.env .

# Chạy script (bỏ qua clone và tạo .env)
.\setup.ps1 -SkipClone
```

Không cần cài Node.js, pnpm, opencode — mọi thứ ở trong Docker image.

---

## 7. Cập nhật phiên bản Open Design mới

Khi image `vanjayak/open-design:latest` được publish bản mới:

```bash
cd deploy
docker compose build --pull
docker compose up -d
```

Giải thích:
- `--pull` buộc Docker kéo base image mới nhất
- `Dockerfile.daemon` kế thừa base image → tự động có bản mới
- Proxy (`Dockerfile.proxy`) không phụ thuộc version API → tương thích mọi phiên bản
- Tools container tự động build lại với base mới

---

## 8. Xử lý sự cố thường gặp

### Daemon không healthy (SQLITE_READONLY)

Nguyên nhân: user sai (container chạy với user khác user tạo database).

```bash
docker compose down
docker volume rm open_design_data  # Xóa database cũ
docker compose up -d
```

### EROFS: read-only file system

Nguyên nhân: opencode (Bun runtime) cần ghi vào thư mục home nhưng container read-only.

Kiểm tra docker-compose.yml có dòng:

```yaml
tmpfs:
  - /tmp
  - /home/open-design:uid=1001,gid=1001
```

Và environment có:

```yaml
HOME: /home/open-design
```

### 401 Unauthorized khi gọi API

Kiểm tra proxy container đang chạy:

```bash
docker compose logs proxy
```

Phải thấy: `auth-proxy listening :7456 -> open-design:7456`

### opencode không available

```bash
# Kiểm tra binary trong daemon container
docker compose exec open-design which opencode-cli

# Kiểm tra symlink
docker compose exec open-design ls -la /usr/local/bin/opencode-cli
```

---

## 9. Cấu hình tùy chọn

### Thay đổi cổng

Sửa `OPEN_DESIGN_PORT` trong `.env`:

```
OPEN_DESIGN_PORT=8080
```

### Giới hạn bộ nhớ

```
OPEN_DESIGN_MEM_LIMIT=512m
```

### Thêm agent CLI khác (Claude Code, Codex, ...)

Sửa `Dockerfile.daemon`, thêm lệnh cài đặt:

```dockerfile
RUN npm install -g @anthropic-ai/claude-code
```

Hoặc copy binary từ image khác tương tự opencode.
