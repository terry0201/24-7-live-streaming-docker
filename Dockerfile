# 使用輕量且功能完整的 FFmpeg 鏡像
FROM jrottenberg/ffmpeg:latest

# 設定工作目錄
WORKDIR /app

# 將本地影片複製到鏡像內的 /app 資料夾
COPY video.mp4 /app/video.mp4

# 設定環境變數預設值 (之後可以在運行時覆蓋)
ENV YOUTUBE_URL=rtmp://a.rtmp.youtube.com/live2
ENV STREAM_KEY=your-default-key

# 執行推流指令
# 使用 sh -c 以支援環境變數替換
ENTRYPOINT ["sh", "-c"]
CMD ["ffmpeg -re -stream_loop -1 -i /app/video.mp4 -c copy -f flv ${YOUTUBE_URL}/${STREAM_KEY}"]