#!/bin/bash
# WebDAVPhotoViewer -> GitHub 自动同步脚本
# 仅在有文件变更时才提交并推送，无变更则直接退出（不产生空提交）。
set -e
cd /Users/hejialiang/WorkBuddy/2026-09-07-21-28-54/WebDAVPhotoViewer

git add -A
if git diff --cached --quiet; then
  echo "$(date '+%Y-%m-%d %H:%M') 无变更，跳过同步"
  exit 0
fi

TS=$(date '+%Y-%m-%d %H:%M')
git commit -m "auto-sync: $TS" >/dev/null
git push origin main
echo "$(date '+%Y-%m-%d %H:%M') 已同步到 GitHub ($(git rev-parse --short HEAD))"
