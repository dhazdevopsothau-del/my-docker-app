# my-docker-app

Stack triển khai dịch vụ Docker hoàn chỉnh với reverse proxy, SSL tự động, tunnel ra ngoài Internet, và các công cụ quản lý/monitoring.

## Kiến trúc tổng quan

```
Internet
  │
  ▼
Cloudflare Edge
  │  (Cloudflare Tunnel — không cần mở port)
  ▼
cloudflared (container)
  │
  ▼
Caddy (reverse proxy + SSL tự động)
  ├── app.domain.com      → Node.js App    [basic auth]
  ├── portainer.domain.com → Portainer     [auth riêng]
  ├── logs.domain.com     → Dozzle         [basic auth]
  └── files.domain.com    → Filebrowser    [basic auth]

Team nội bộ
  │
  ▼
Tailscale VPN → Caddy (qua IP tailscale của máy chủ)
```

### Các thành phần

| Service | Image | Mục đích |
|---|---|---|
| **Caddy** | `lucaslorentz/caddy-docker-proxy` | Reverse proxy, SSL Let's Encrypt tự động, đọc routes từ Docker labels |
| **cloudflared** | `cloudflare/cloudflared` | Tunnel ra Internet, không cần mở port 80/443 trên firewall |
| **Tailscale** | `tailscale/tailscale` | VPN cho team nội bộ truy cập |
| **Node.js App** | build từ `./services/app` | Dịch vụ chính Hello World, ghi log ra file |
| **Portainer** | `portainer/portainer-ce` | Quản lý Docker toàn diện: container, image, volume, network |
| **Dozzle** | `amir20/dozzle` | Xem log realtime của tất cả container qua web UI |
| **Filebrowser** | `filebrowser/filebrowser` | Duyệt, xem, tải file log qua web UI |

---

## Yêu cầu hệ thống

- Docker >= 24.x
- Docker Compose >= 2.x
- Git
- Tên miền trỏ về Cloudflare (để dùng tunnel)

---

## Cài đặt lần đầu

### 1. Clone repo và chuẩn bị .env

```bash
git clone https://github.com/your/repo.git
cd my-docker-app
cp .env.example .env
```

Mở `.env` và điền đầy đủ các giá trị (xem phần **Cấu hình .env** bên dưới).

### 2. Tạo bcrypt hash cho mật khẩu Caddy

```bash
docker run --rm caddy:alpine caddy hash-password --plaintext "matkhauCuaBan"
```

Copy output (bắt đầu bằng `$2a$14$...`) vào `CADDY_AUTH_HASH` trong `.env`.

### 3. Tạo Cloudflare Tunnel

1. Vào [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Networks → Tunnels**
2. **Create a tunnel** → chọn **Cloudflared** → đặt tên tunnel
3. Copy **Token** → điền vào `CF_TUNNEL_TOKEN` trong `.env`
4. Cấu hình **Public Hostnames** trong dashboard:

| Subdomain | Domain | Service |
|---|---|---|
| `app` | `yourdomain.com` | `http://caddy:80` |
| `portainer` | `yourdomain.com` | `http://caddy:80` |
| `logs` | `yourdomain.com` | `http://caddy:80` |
| `files` | `yourdomain.com` | `http://caddy:80` |

### 4. Cài GitHub Actions Self-hosted Runner

```bash
# Trên máy chủ của bạn:
mkdir -p ~/actions-runner && cd ~/actions-runner

# Lấy lệnh cài đặt từ:
# GitHub repo → Settings → Actions → Runners → New self-hosted runner
# Chọn Linux → copy và chạy các lệnh hướng dẫn

# Cài làm service chạy nền (chạy một lần):
sudo ./svc.sh install
sudo ./svc.sh start
```

Sau khi cài, runner xuất hiện tại **Settings → Actions → Runners** với trạng thái **Idle**.

> **Azure DevOps**: Vào **Project Settings → Agent pools → Add pool** → Self-hosted → thêm agent tương tự.

### 5. Khởi động lần đầu (thủ công)

```bash
# Trên máy chủ, tại thư mục project:
docker compose up -d --build
```

Hoặc push code lên nhánh `main` — pipeline tự động chạy.

### Artifacts sau mỗi lần CI/CD chạy

- **Azure Pipelines** và **GitHub Actions** đều thu thập artifacts runtime sau deploy.
- Artifact tên `docker-runtime` bao gồm:
  - trạng thái container/images (`docker compose ps/images`, `docker ps/images`),
  - log tổng hợp (`docker compose logs`),
  - `docker inspect` + log riêng cho từng container,
  - snapshot thư mục `logs/` (nếu có).
- Mục đích: hỗ trợ debug nhanh khi deploy lỗi hoặc service bất thường.

---

## Cấu hình .env

### DOMAIN & EMAIL

```env
DOMAIN=yourdomain.com
```
Domain chính. Tất cả subdomains sẽ là `xxx.yourdomain.com`.

```env
CADDY_EMAIL=admin@yourdomain.com
```
Email để Let's Encrypt gửi thông báo khi cert sắp hết hạn. Caddy tự gia hạn cert.

---

### Caddy Basic Auth

```env
CADDY_AUTH_USER=admin
CADDY_AUTH_HASH=$2a$14$...
```

- `CADDY_AUTH_USER`: tên đăng nhập (dùng chung cho app, dozzle, filebrowser)
- `CADDY_AUTH_HASH`: bcrypt hash của mật khẩu

**Tạo hash:**
```bash
docker run --rm caddy:alpine caddy hash-password --plaintext "matkhauMoi"
```

**Lưu ý:** Portainer có trang login riêng nên không dùng Caddy basic auth. Lần đầu vào `portainer.domain.com` sẽ tạo tài khoản admin.

---

### Cloudflare Tunnel

```env
CF_TUNNEL_TOKEN=eyJhI...
```

Token lấy từ Cloudflare Zero Trust → Tunnels. Token đã bao gồm thông tin tunnel ID và credentials, không cần file config riêng.

---

### Tailscale

```env
TS_AUTHKEY=tskey-auth-xxxxx
```

Auth key để máy chủ tự động join Tailscale network. Tạo tại [Tailscale Admin → Keys](https://login.tailscale.com/admin/settings/keys).

Nên tích:
- **Reusable**: để dùng lại khi restart container
- **Ephemeral**: tự xoá khỏi network nếu mất kết nối lâu

Sau khi chạy, team kết nối Tailscale VPN rồi truy cập `http://<IP-tailscale>` là vào được Caddy.

---

### Node.js App

```env
APP_PORT=3000
NODE_ENV=production
LOG_DIR=/app/logs
```

- `APP_PORT`: port bên trong container, Caddy proxy vào đây
- `LOG_DIR`: đường dẫn log bên trong container, được mount ra `./logs/app/` trên host

---

### Subdomains

```env
PORTAINER_SUBDOMAIN=portainer
DOZZLE_SUBDOMAIN=logs
FILEBROWSER_SUBDOMAIN=files
```

Tùy chỉnh subdomain cho từng dịch vụ. Mặc định:
- `portainer.yourdomain.com`
- `logs.yourdomain.com`
- `files.yourdomain.com`

---

## Truy cập các dịch vụ

| URL | Dịch vụ | Auth |
|---|---|---|
| `https://app.yourdomain.com` | Node.js Hello World | Caddy basic auth |
| `https://portainer.yourdomain.com` | Portainer dashboard | Login Portainer |
| `https://logs.yourdomain.com` | Dozzle — log realtime | Caddy basic auth |
| `https://files.yourdomain.com` | Filebrowser — log files | Caddy basic auth |

---

## Thêm dịch vụ mới

Chỉ cần thêm vào `docker-compose.yml` với labels tương ứng:

```yaml
  my-new-service:
    image: some-image:latest
    labels:
      caddy: "new.${DOMAIN}"
      caddy.reverse_proxy: "{{upstreams 8000}}"
      # Thêm basic auth nếu cần:
      caddy.basicauth: "/*"
      caddy.basicauth.${CADDY_AUTH_USER}: "${CADDY_AUTH_HASH}"
    networks: [app_net]
```

Push code → pipeline tự deploy. Không cần sửa gì thêm.

---

## Cấu trúc thư mục

```
my-docker-app/
├── .env.example               # Template cấu hình (copy thành .env)
├── .gitignore
├── docker-compose.yml         # Stack chính
├── azure-pipelines.yml        # CI/CD Azure DevOps
├── README.md
│
├── .github/
│   └── workflows/
│       └── deploy.yml         # CI/CD GitHub Actions
│
├── cloudflared/
│   └── config.yml.example     # Template config tunnel (nếu không dùng token)
│
├── services/
│   └── app/                   # Node.js service
│       ├── Dockerfile
│       ├── package.json
│       └── index.js
│
└── logs/                      # Log files (gitignored, tạo khi chạy)
    └── app/
        └── app.log
```

---

## Lệnh thường dùng

```bash
# Khởi động toàn bộ stack
docker compose up -d

# Build lại và khởi động (sau khi sửa code)
docker compose up -d --build

# Xem log realtime tất cả service
docker compose logs -f

# Xem log một service cụ thể
docker compose logs -f app

# Restart một service
docker compose restart app

# Dừng toàn bộ stack
docker compose down

# Dừng và xoá volumes (reset hoàn toàn)
docker compose down -v

# Xem trạng thái
docker compose ps

# Vào shell trong container
docker compose exec app sh
```

---

## Lưu ý bảo mật

- File `.env` chứa secrets — **không bao giờ commit lên git**
- Portainer có quyền quản lý toàn bộ Docker — nên đặt mật khẩu mạnh
- Caddy basic auth là HTTP Basic Auth — chỉ nên dùng với HTTPS (đã có SSL)
- Cloudflare Tunnel không cần mở port 22, 80, 443 trên firewall — chỉ cần outbound internet
