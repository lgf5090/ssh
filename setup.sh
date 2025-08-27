#!/bin/bash

# setup.sh - SSH密钥解密和安装脚本
# 用于从 https://github.com/lgf5090/ssh.git 仓库安装SSH密钥
echo "=== SSH密钥一键安装工具 ==="
echo "仓库: https://github.com/lgf5090/ssh.git"

# 设置变量
KEY_NAME="id_ed25519"
ENCRYPTED_KEY="$KEY_NAME.encrypted"
SSH_DIR="$HOME/.ssh"
REPO_URL="https://github.com/lgf5090/ssh.git"
TEMP_DIR="/tmp/ssh-setup-$$"

# 检查openssl是否安装
if ! command -v openssl &> /dev/null; then
    echo "❌ 错误：openssl 未安装。"
    echo "请先安装openssl："
    echo "Ubuntu/Debian: sudo apt-get install openssl"
    echo "CentOS/RHEL: sudo yum install openssl"
    echo "macOS: 通常已预装"
    exit 1
fi

# 创建临时目录
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# 下载仓库文件
echo "下载SSH密钥文件..."
if ! curl -s -O "https://raw.githubusercontent.com/lgf5090/ssh/main/$ENCRYPTED_KEY" && \
   ! curl -s -O "https://raw.githubusercontent.com/lgf5090/ssh/main/$KEY_NAME.pub"; then
    echo "❌ 下载文件失败！请检查网络连接和仓库地址。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 检查文件是否下载成功
if [ ! -f "$ENCRYPTED_KEY" ] || [ ! -f "$KEY_NAME.pub" ]; then
    echo "❌ 文件下载不完整！请检查仓库中文件是否存在。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ 文件下载完成"

# 创建~/.ssh目录（如果不存在）
mkdir -p "$SSH_DIR"

# 解密私钥
echo "开始解密SSH私钥..."
read -sp "请输入解密密码: " password
echo

if ! openssl aes-256-cbc -d -salt -in "$ENCRYPTED_KEY" -out "$SSH_DIR/$KEY_NAME" -pass pass:"$password" 2>/dev/null; then
    echo "❌ 解密失败！请检查："
    echo "   - 密码是否正确"
    echo "   - 加密文件是否完整"
    rm -f "$SSH_DIR/$KEY_NAME"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 复制公钥
cp "$KEY_NAME.pub" "$SSH_DIR/"

# 设置严格的权限（SSH安全要求）
echo "设置文件权限..."
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/$KEY_NAME"      # 私钥：只有用户可读写
chmod 644 "$SSH_DIR/$KEY_NAME.pub"  # 公钥：用户可读写，其他可读

# 清理临时文件
rm -rf "$TEMP_DIR"

echo ""
echo "✅ 安装完成！"
echo "📁 SSH目录: $SSH_DIR/"
echo "🔐 私钥文件: $SSH_DIR/$KEY_NAME"
echo "🔓 公钥文件: $SSH_DIR/$KEY_NAME.pub"
echo ""

# 显示公钥内容（方便用户添加到GitHub等）
echo "=== 公钥内容 ==="
cat "$SSH_DIR/$KEY_NAME.pub"
echo ""

# 测试SSH连接（可选）
read -p "是否测试SSH连接到github.com？(y/n): " test_ssh
if [ "$test_ssh" = "y" ] || [ "$test_ssh" = "Y" ]; then
    echo "测试连接中..."
    ssh -T git@github.com
fi

echo ""
echo "💡 下一步操作："
echo "1. 将上面的公钥内容添加到GitHub: Settings → SSH and GPG keys → New SSH key"
echo "2. 测试连接: ssh -T git@github.com"
echo "3. 开始使用SSH进行git操作"
