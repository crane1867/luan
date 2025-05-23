#!/bin/bash

# 1. 要切片的视频路径
VIDEO_PATH="$1"

# 2. 输出目录
OUTPUT_DIR="/home/docker/qbittorrent/downloads/sliced"
mkdir -p "$OUTPUT_DIR"

# 3. 检查 ffmpeg 是否安装
if ! command -v ffmpeg &> /dev/null; then
    echo "未检测到 ffmpeg，尝试安装..."
    apt update && apt install -y ffmpeg || {
        echo "❌ ffmpeg 安装失败，请手动安装后重试。"
        exit 1
    }
fi

# 4. 获取文件名（不含路径和扩展）
VIDEO_NAME=$(basename "$VIDEO_PATH")
BASE_NAME="${VIDEO_NAME%.*}"

# 5. 切片输出路径
SLICE_DIR="$OUTPUT_DIR/$BASE_NAME"
mkdir -p "$SLICE_DIR"

# 6. 执行切片
echo "🎬 正在切片视频：$VIDEO_PATH ..."
ffmpeg -i "$VIDEO_PATH" \
  -codec: copy -start_number 0 \
  -hls_time 10 -hls_list_size 0 \
  -f hls "$SLICE_DIR/index.m3u8" || {
    echo "❌ 切片失败。"
    exit 1
}

# 7. 创建播放器 HTML 文件
cat > "$SLICE_DIR/player.html" <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>HLS 播放器 - $BASE_NAME</title>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</head>
<body>
<style>
    * {
        margin: 0;
        padding: 0;
        overflow: hidden; /* 隐藏全局滚动条 */
    }

    .video-container {
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        display: flex;
        justify-content: center;
        align-items: center;
        background: black; /* 视频未加载时的背景色 */
    }

    #video {
        max-width: 100%;
        max-height: 100%;
        object-fit: contain; /* 保持原始比例适配容器 */
    }
</style>

<div class="video-container">
    <video id="video" controls autoplay></video>
</div>
  <h2>$BASE_NAME 视频播放器</h2>
  <script>
    var video = document.getElementById('video');
    var videoSrc = 'index.m3u8';

    if (Hls.isSupported()) {
      var hls = new Hls();
      hls.loadSource(videoSrc);
      hls.attachMedia(video);
    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = videoSrc;
    }
  </script>
</body>
</html>
EOF

echo "✅ 切片完成，可访问播放器："
echo "   https://xxx.com/sliced/$BASE_NAME/player.html"
