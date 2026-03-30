# Hướng dẫn chuẩn bị để chạy repo bằng GitHub Actions

Tài liệu này tổng hợp chính xác các điều kiện để workflow `.github/workflows/deploy.yml` chạy thành công.

## 1) Hiểu workflow hiện tại đang chạy kiểu gì

Workflow deploy của repo này chạy với:
- trigger: `push` vào nhánh `main` hoặc chạy tay bằng `workflow_dispatch`
- runner: `runs-on: self-hosted`

Điều này có nghĩa là **bắt buộc** bạn phải có máy chạy self-hosted runner (không chạy được trên GitHub-hosted runner mặc định nếu chưa sửa workflow).

## 2) Checklist bắt buộc trước khi chạy

## 2.1. Trên GitHub repo

1. Bật Actions trong repo (Settings → Actions).
2. Tạo self-hosted runner:
   - vào `Settings → Actions → Runners → New self-hosted runner`
   - chọn Linux và chạy đầy đủ các lệnh GitHub cung cấp trên máy chủ của bạn.
3. Đảm bảo runner đang trạng thái **Idle/Online**.

## 2.2. Trên máy self-hosted runner

Cần có sẵn:
- Docker Engine
- Docker Compose plugin (`docker compose`)
- Git
- Quyền chạy Docker cho user runner

Nên kiểm tra nhanh:

```bash
docker --version
docker compose version
git --version
docker ps
```

Nếu `docker ps` báo permission denied, thêm user runner vào nhóm docker và đăng nhập lại:

```bash
sudo usermod -aG docker <runner-user>
```

## 2.3. Trong repo trên máy runner

Workflow yêu cầu file `.env` có sẵn tại root repo. Nếu không có thì job fail ở step `Check .env exists`.

Chuẩn bị như sau:

```bash
cp .env.example .env
# sau đó chỉnh sửa đầy đủ biến trong .env
```

Các biến quan trọng tối thiểu:
- `DOMAIN`
- `CADDY_EMAIL`
- `CADDY_AUTH_USER`
- `CADDY_AUTH_HASH`
- `CF_TUNNEL_TOKEN`
- `TS_AUTHKEY`
- `APP_PORT`, `NODE_ENV`, `LOG_DIR`
- các subdomain (`PORTAINER_SUBDOMAIN`, `DOZZLE_SUBDOMAIN`, `FILEBROWSER_SUBDOMAIN`)

## 2.4. Dịch vụ ngoài cần chuẩn bị trước

1. **Cloudflare Tunnel** đã được tạo và lấy `CF_TUNNEL_TOKEN`.
2. DNS/public hostnames trong Cloudflare đã map đúng về `http://caddy:80`.
3. **Tailscale auth key** hợp lệ cho `TS_AUTHKEY`.
4. Hash bcrypt cho Caddy auth đã tạo đúng format `$2a$...`.

## 3) Cách chạy thử an toàn trước khi push

Trên chính máy self-hosted runner, test local trước:

```bash
docker compose pull
docker compose up -d --build --remove-orphans
docker compose ps
```

Nếu local chạy ổn mới push lên `main` để Actions deploy tự động.

## 4) Cách kích hoạt workflow

Có 2 cách:
1. Push commit vào nhánh `main`.
2. Vào tab Actions → workflow **Deploy Stack** → **Run workflow** (workflow_dispatch).

## 5) Các lỗi thường gặp và cách xử lý nhanh

1. **`ERROR: .env file not found`**
   - Chưa có `.env` trong workspace runner.
   - Fix: tạo `.env` từ `.env.example` và điền đủ biến.

2. **`Cannot connect to the Docker daemon`**
   - User runner không có quyền Docker hoặc Docker daemon chưa chạy.
   - Fix: chạy Docker daemon, thêm user vào group `docker`.

3. **Runner offline / job bị queue mãi**
   - Service runner chưa chạy.
   - Fix: vào máy runner, kiểm tra service và start lại.

4. **Container lên nhưng app không truy cập được qua domain**
   - Sai Cloudflare hostname/tunnel hoặc sai subdomain env.
   - Fix: đối chiếu lại hostname mapping và biến môi trường.

## 6) Gợi ý bảo mật

- Không commit `.env` vào git.
- Nên dùng GitHub Environments/Secrets nếu bạn muốn chuyển dần sang inject biến ở runtime.
- Giới hạn quyền runner (repo cụ thể, máy riêng, network policy phù hợp).
