# EC2 Docker 24/7 影片串流全攻略

這是一份針對 AWS EC2 (特別是 t3.micro) 進行 24/7 影片串流的實戰指南。結合了權限處理、效能優化以及成本控管的經驗總結。

---

## 📋 目錄
- 第一階段：環境與權限架設
- 第二階段：Docker 鏡像封裝
- 第三階段：部署與執行
- 第四階段：地雷區與錯誤排除
- 🛠️ 常用調試工具箱

---

## 🚀 第一階段：環境與權限架設

### 1. IAM 角色設定 (身分證)
**不要**在機器內手動輸入 Access Key。請在 IAM 控制台建立一個 Role：
- **角色類型**：EC2
- **權限設定**：附加 `AmazonEC2ContainerRegistryReadOnly`
- **綁定**：在 EC2 控制台將此 Role 綁定至你的執行個體。

### 2. 系統初始化
連入 EC2 後，優先解決 1GB 記憶體不足與 Docker 權限問題：

```bash
# --- 增加 Swap 空間 (預防 t3.micro 假死) ---
sudo dd if=/dev/zero of=/swapfile bs=128M count=16
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# --- 安裝並啟動 Docker ---
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker

# --- 權限修復 (免 sudo) ---
sudo usermod -aG docker ec2-user
newgrp docker 
```

---

## 📦 第二階段：Docker 鏡像封裝

### 1. 專案目錄結構
```text
my-stream-bot/
├── Dockerfile
└── video.mp4    <-- 你的影片檔案
```

### 2. Dockerfile 撰寫
> [!IMPORTANT]
> 必須使用 `sh -c` 才能正確解析環境變數。

```dockerfile
FROM jrottenberg/ffmpeg:latest
WORKDIR /app
COPY video.mp4 /app/video.mp4

# 設定預設網址
ENV YOUTUBE_URL=rtmp://a.rtmp.youtube.com/live2

# 必須使用 sh -c 才能解析 ${VARIABLE}
ENTRYPOINT ["sh", "-c"]
CMD ["ffmpeg -re -stream_loop -1 -i /app/video.mp4 -c:v copy -c:a copy -fflags +genpts -flvflags no_duration_filesize -f flv ${YOUTUBE_URL}/${STREAM_KEY}"]
```

---

## 🚢 第三階段：部署與執行

### 1. 從本地推送至 ECR
每次修改 Dockerfile 或影片後執行：
```bash
docker build --no-cache -t live-stream .
docker tag live-stream <ECR_URL>:latest
docker push <ECR_URL>:latest
```

### 2. 在 EC2 啟動串流
```bash
# 驗證身分 (應顯示關聯的 Role)
aws sts get-caller-identity

# 登入 ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <你的帳號ID>.dkr.ecr.us-east-1.amazonaws.com

# 強制拉取最新版
docker pull <ECR_URL>:latest

# 啟動容器 (限制資源預防崩潰)
docker run -d \
  --name yt-streamer \
  --memory="700m" \
  --restart always \
  -e STREAM_KEY="你的實際金鑰" \
  <ECR_URL>:latest
```

---

## ⚠️ 第四階段：地雷區與錯誤排除

### 🚩 地雷 1：EC2 流量帳單炸彈
- **慘痛教訓**：EC2 免費額度僅 100GB。以 3Mbps 串流，約 3 天就會刷爆。
- **解決方案**：改用 **AWS Lightsail** ($5 方案含 2TB) 或 **Oracle Cloud** (10TB 免費)。

### 🚩 地雷 2：t3.micro 突然斷線 (CPU Credit)
- **慘痛教訓**：t 系列有積分制，積分耗盡效能會掉到 10%，導致 SSH 斷開。
- **解決方案**：務必使用 `-c:v copy` (不轉碼)，並監控 CPU Credit Balance。

### 🚩 地雷 3：YouTube 顯示「No Data」
- **排查清單**：
  1. `docker logs yt-streamer` 是否有 bitrate 數據？
  2. 若有數據但無畫面，檢查 `STREAM_KEY` 是否正確。
  3. 確認 Dockerfile 是否包含 `sh -c`。

---

## 🛠️ 常用調試工具箱
```bash
# 查看即時串流日誌
docker logs -f yt-streamer

# 觀察系統負載
top

# 測試 YouTube RTMP 連線
nc -zv a.rtmp.youtube.com 1935
```