這是一份為你彙整的 EC2 Docker 24/7 影片串流全攻略。這份清單結合了我們前面的實戰經驗、權限報錯處理以及針對 t3.micro 效能榨乾的優化建議。

🚀 第一階段：環境與權限架設 (基礎建設)

1. IAM 角色 (身分證)

不要在機器內輸入金鑰，請在 IAM 控制台建立一個 Role：

角色類型： EC2。

權限設定： 附加 AmazonEC2ContainerRegistryReadOnly。

綁定： 在 EC2 控制台將此 Role 綁定至你的執行個體。

2. 系統初始化 (解決卡頓與權限)

連入 EC2 後，第一步先解決 1GB 記憶體不足 與 Docker 權限 問題：

Bash

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
newgrp docker # 立即生效


📦 第二階段：Docker 鏡像封裝 (核心邏輯)

專案目錄結構

請在你的電腦（或開發環境）建立一個資料夾，結構如下：

my-stream-bot/
├── Dockerfile
└── video.mp4    <-- 你的影片檔案

3. Dockerfile 的「變數陷阱」修復

絕對不能直接寫 CMD ["ffmpeg", ...]，否則環境變數會失效。

Dockerfile

FROM jrottenberg/ffmpeg:latest
WORKDIR /app
COPY video.mp4 /app/video.mp4

# 設定預設網址
ENV YOUTUBE_URL=rtmp://a.rtmp.youtube.com/live2

# 必須使用 sh -c 才能解析 ${VARIABLE}
ENTRYPOINT ["sh", "-c"]
CMD ["ffmpeg -re -stream_loop -1 -i /app/video.mp4 -c:v copy -c:a copy -fflags +genpts -flvflags no_duration_filesize -f flv ${YOUTUBE_URL}/${STREAM_KEY}"]


🚢 第三階段：部署與執行 (實戰操作)

4. 從本地推送至 ECR

每次修改 Dockerfile 或影片後：

Build: docker build --no-cache -t live-stream .

Tag: docker tag live-stream <ECR_URL>:latest

Push: docker push <ECR_URL>:latest

5. 在 EC2 啟動串流

# 0. 驗證:應該會看到一串 JSON，顯示這台機器已經變成了剛才那個 Role
aws sts get-caller-identity

# 1. 登入 ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <你的帳號ID>.dkr.ecr.us-east-1.amazonaws.com

# 2. 強制拉取最新版 (避免快取舊鏡像)
docker pull <ECR_URL>:latest

# 3. 限制資源啟動 (預防 t3.micro 崩潰)
docker run -d \
  --name yt-streamer \
  --memory="700m" \
  --restart always \
  -e STREAM_KEY="你的實際金鑰" \
  <ECR_URL>:latest


⚠️ 第四階段：地雷區與錯誤排除 (踩雷總結)

🚩 地雷 1：EC2 流量帳單炸彈

慘痛教訓： EC2 免費額度僅 100GB。以 3Mbps 串流，約 3 天 就會刷爆信用卡。

解決方案： 改用 AWS Lightsail $5 方案 (含 2TB 流量) 或 Oracle Cloud (10TB 免費)。

🚩 地雷 2：t3.micro 突然斷線 (CPU Credit)

慘痛教訓： t 系列有積分制，積分用完效能會掉到剩 10%，導致 SSH 斷開。

解決方案： 務必使用 -c:v copy (不轉碼)，並在控制台監控 CPU Credit Balance。

🚩 地雷 3：YouTube 顯示「No Data」

排查清單：

檢查 docker logs yt-streamer 是否看到 bitrate=... 在跳動？

若有跳動但無畫面 100% 是 Stream Key 寫錯 或 Dockerfile 沒加 sh -c。

使用 docker exec yt-streamer env 確認變數有沒有真的進去。

🚩 地雷 4：Docker Push 了但 EC2 沒更新

慘痛教訓： Docker 不會自動下載新鏡像。

解決方案： 必須先 docker rm -f 舊容器，手動 docker pull 後再重開。

🛠️ 常用調試工具箱

看即時數據： docker logs -f yt-streamer

看資源佔用： top (觀察 load average)

測試 YouTube 連線： nc -zv a.rtmp.youtube.com 1935