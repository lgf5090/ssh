#!/bin/bash

# generate-ssh-key.sh - SSH密钥生成和加密脚本
echo "=== SSH密钥生成和加密工具 ==="

# 设置变量
KEY_NAME="id_ed25519"
SSH_DIR="$HOME/.ssh"
TARGET_DIR="$HOME/code/ssh"
ENCRYPTED_KEY="$KEY_NAME.encrypted"

# 检查目标目录是否存在，不存在则创建
mkdir -p "$TARGET_DIR"

# 检查是否已存在密钥
if [ -f "$SSH_DIR/$KEY_NAME" ]; then
    echo "⚠️  发现已存在的密钥: $SSH_DIR/$KEY_NAME"
    read -p "是否覆盖？(y/n): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "操作已取消。"
        exit 1
    fi
fi

# 生成新的SSH密钥（无密码）
echo "生成新的ED25519 SSH密钥..."
ssh-keygen -t ed25519 -f "$SSH_DIR/$KEY_NAME" -N ""

if [ $? -eq 0 ]; then
    echo "✅ SSH密钥生成成功！"
else
    echo "❌ SSH密钥生成失败！"
    exit 1
fi

# 加密私钥
echo "加密私钥文件..."
read -sp "请设置加密密码: " encrypt_password
echo
read -sp "请再次确认密码: " confirm_password
echo

if [ "$encrypt_password" != "$confirm_password" ]; then
    echo "❌ 密码不一致！"
    rm -f "$SSH_DIR/$KEY_NAME" "$SSH_DIR/$KEY_NAME.pub"
    exit 1
fi

# 使用openssl加密私钥
openssl aes-256-cbc -salt -in "$SSH_DIR/$KEY_NAME" -out "$TARGET_DIR/$ENCRYPTED_KEY" -pass pass:"$encrypt_password"

if [ $? -eq 0 ]; then
    echo "✅ 私钥加密成功！"
else
    echo "❌ 私钥加密失败！"
    exit 1
fi

# 复制公钥到目标目录
cp "$SSH_DIR/$KEY_NAME.pub" "$TARGET_DIR/"

# 设置文件权限
chmod 600 "$TARGET_DIR/$ENCRYPTED_KEY"
chmod 644 "$TARGET_DIR/$KEY_NAME.pub"

echo ""
echo "=== 操作完成 ==="
echo "📁 原始密钥位置: $SSH_DIR/"
echo "📁 加密文件位置: $TARGET_DIR/"
echo "🔐 加密私钥: $TARGET_DIR/$ENCRYPTED_KEY"
echo "🔓 公钥文件: $TARGET_DIR/$KEY_NAME.pub"
echo ""
echo "💡 下一步: 将加密的私钥和公钥文件提交到Git仓库"
echo "💡 重要: 请牢记你设置的加密密码: '$encrypt_password'"
echo "💡 安全提示: 建议备份加密密码到安全的地方"
