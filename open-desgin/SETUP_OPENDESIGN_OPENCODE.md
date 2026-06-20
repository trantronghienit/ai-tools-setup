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

## 2. Clone dự án

```bash
git clone <repo-url> open-design
cd open-design/deploy
```

Các file quan trọng trong thư mục `deploy/`:

| File | Chức năng |
|------|-----------|
| `docker-compose.yml` | Định nghĩa 3 service |
| `Dockerfile.daemon` | Mở rộng image published, cài opencode |
| `Dockerfile.proxy` | Proxy thêm Bearer token |
| `Dockerfile.tools` | Image chứa od CLI + opencode |
| `proxy/proxy.mjs` | Mã nguồn proxy |
| `.env` | Biến môi trường (OD_API_TOKEN, ...) |

---

## 3. Tạo file .env

```bash
cp .env.example .env
```

Sinh token ngẫu nhiên:

```bash
# Linux/macOS
openssl rand -hex 32

# Windows (PowerShell)
# Dùng https://acte.ltd/utils/randomkey hoặc:
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Sửa file `.env`, đặt giá trị cho `OD_API_TOKEN`:

```
OD_API_TOKEN=ec6a6a779f191034b1e3f2f610b51995797569b86a3c084a02b61f0821fc0a7
```

---

## 4. Build images

```bash
cd deploy
docker compose build
```

Lần đầu có thể mất vài phút (tải base image ~400MB + opencode ~150MB). Các lần sau dùng cache.

---

## 5. Khởi động

```bash
docker compose up -d
```

Kiểm tra trạng thái:

```bash
docker compose ps
```

Kết quả mong đợi:

```
NAME                IMAGE               STATUS                    PORTS
open-design         open-design:local   Up (healthy)              7456/tcp
open-design-proxy   open-design-proxy   Up                        127.0.0.1:7456->7456/tcp
open-design-tools   open-design-tools   Up
```

## 6. Kiểm tra hoạt động

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

## 7. Sử dụng OpenCode CLI

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

## 8. Sao lưu và triển khai trên máy khác

### File cần copy

Chỉ cần copy thư mục `deploy/` (loại bỏ file tạm):

```
deploy/
├── docker-compose.yml
├── Dockerfile.daemon
├── Dockerfile.proxy
├── Dockerfile.tools
├── proxy/
│   └── proxy.mjs
├── .env          (hoặc .env.example + tự tạo token)
└── .env.example
```

### Trên máy mới

```bash
git clone <repo-url> open-design
cd open-design/deploy
cp .env.example .env
# Sửa .env với token mới
docker compose build
docker compose up -d
```

Không cần cài đặt gì thêm (Node.js, pnpm, opencode) — mọi thứ đều ở trong Docker image.

---

## 9. Cập nhật phiên bản Open Design mới

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

## 10. Xử lý sự cố thường gặp

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

## 11. Cấu hình tùy chọn

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
