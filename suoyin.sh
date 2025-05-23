#!/bin/bash

SLICE_BASE="/home/docker/qbittorrent/downloads/sliced"
INDEX_HTML="$SLICE_BASE/index.html"

echo "📄 正在生成索引页：$INDEX_HTML"

cat > "$INDEX_HTML" <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>视频索引 - sliced</title>
</head>
<body>
  <h2>可用视频列表：</h2>
  <ul>
EOF

# 遍历每个子目录
for dir in "$SLICE_BASE"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    echo "    <li><a href=\"$name/player.html\">$name</a></li>" >> "$INDEX_HTML"
done

cat >> "$INDEX_HTML" <<EOF
  </ul>
</body>
</html>
EOF

echo "✅ 索引页已生成：https://xxx.xxx"
