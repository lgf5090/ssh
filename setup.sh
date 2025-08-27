#!/bin/bash

# setup.sh - SSH密钥批量解密和安装脚本
# 用于从 https://github.com/lgf5090/ssh.git 仓库批量安装SSH密钥和配置
echo "=== SSH密钥批量安装工具 ==="
echo "仓库: https://github.com/lgf5090/ssh.git"

# 设置变量
SSH_DIR="$HOME/.ssh"
REPO_URL="https://github.com/lgf5090/ssh.git"
TEMP_DIR="/tmp/ssh-setup-$$"
RAW_BASE_URL="https://raw.githubusercontent.com/lgf5090/ssh/main"

# 检查openssl是否安装
if ! command -v openssl &> /dev/null; then
    echo "❌ 错误：openssl 未安装。"
    echo "请先安装openssl："
    echo "Ubuntu/Debian: sudo apt-get install openssl"
    echo "CentOS/RHEL: sudo yum install openssl"
    echo "macOS: 通常已预装"
    exit 1
fi

# 检查curl是否安装
if ! command -v curl &> /dev/null; then
    echo "❌ 错误：curl 未安装。"
    echo "请先安装curl"
    exit 1
fi

# 创建临时目录
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo "当前工作目录: $(pwd)"
echo "开始下载SSH配置文件..."

# 获取仓库中的文件列表
declare -a ENCRYPTED_FILES=()

# 预定义可能的文件模式
POSSIBLE_ENCRYPTED_PATTERNS=(
    "id_ed25519.encrypted"
    "id_rsa.encrypted" 
    "id_ecdsa.encrypted"
    "id_ed25519.pub.encrypted"
    "id_rsa.pub.encrypted"
    "id_ecdsa.pub.encrypted"
    "config.encrypted"
)

echo "扫描和下载加密文件..."

# 扫描所有可能的加密文件
for encrypted_pattern in "${POSSIBLE_ENCRYPTED_PATTERNS[@]}"; do
    echo "尝试下载 $encrypted_pattern..."
    if curl -f -L -s "$RAW_BASE_URL/$encrypted_pattern" -o "$encrypted_pattern" 2>/dev/null; then
        echo "✅ 下载 $encrypted_pattern 成功"
        ENCRYPTED_FILES+=("$encrypted_pattern")
    else
        echo "⚠️  $encrypted_pattern 不存在，跳过"
    fi
done

# 检查是否下载到任何文件
if [ ${#ENCRYPTED_FILES[@]} -eq 0 ]; then
    echo "❌ 没有找到任何加密的SSH配置文件！"
    echo "请检查仓库: $REPO_URL"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""
echo "📋 发现的加密文件："
printf '  %s\n' "${ENCRYPTED_FILES[@]}"
echo ""

# 创建~/.ssh目录（如果不存在）
mkdir -p "$SSH_DIR"

# 备份现有SSH配置（如果存在）
if [ -d "$SSH_DIR" ] && [ "$(ls -A $SSH_DIR)" ]; then
    backup_dir="$SSH_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    echo "🔄 备份现有SSH配置到: $backup_dir"
    cp -r "$SSH_DIR" "$backup_dir"
fi

# 如果有加密文件，获取解密密码
if [ ${#ENCRYPTED_FILES[@]} -gt 0 ]; then
    echo "🔐 需要解密 ${#ENCRYPTED_FILES[@]} 个加密文件"
    
    # 检查是否通过管道执行，如果是则从/dev/tty读取
    if [ -t 0 ]; then
        # 标准输入是终端，直接读取
        read -sp "请输入解密密码: " password
    else
        # 标准输入被管道占用，从/dev/tty读取
        echo "检测到通过管道执行，请在终端中输入密码："
        read -sp "请输入解密密码: " password < /dev/tty
    fi
    echo
    echo ""
fi

# 解密所有加密文件
success_count=0
for encrypted_file in "${ENCRYPTED_FILES[@]}"; do
    # 提取原始文件名（去掉.encrypted后缀）
    original_name="${encrypted_file%.encrypted}"
    
    echo "🔓 解密 $encrypted_file → $original_name"
    
    if openssl aes-256-cbc -d -salt -in "$encrypted_file" -out "$SSH_DIR/$original_name" -pass pass:"$password" 2>/dev/null; then
        echo "✅ $original_name 解密成功"
        
        # 根据文件类型设置合适的权限
        if [[ "$original_name" == *.pub ]]; then
            # 公钥文件
            chmod 644 "$SSH_DIR/$original_name"
        elif [[ "$original_name" == "config" ]]; then
            # 配置文件
            chmod 600 "$SSH_DIR/$original_name"
        else
            # 私钥文件
            chmod 600 "$SSH_DIR/$original_name"
        fi
        
        ((success_count++))
    else
        echo "❌ $original_name 解密失败！"
        rm -f "$SSH_DIR/$original_name"
    fi
done

# 设置SSH目录权限
chmod 700 "$SSH_DIR"

# 清理临时文件
rm -rf "$TEMP_DIR"

echo ""
echo "✅ 安装完成！"
echo "📁 SSH目录: $SSH_DIR/"
echo "🔐 解密成功的文件: $success_count 个"
echo ""

# 显示SSH目录内容
echo "=== SSH目录内容 ==="
ls -la "$SSH_DIR/"
echo ""

# 显示所有解密后的公钥内容
echo "=== 公钥内容 ==="
find "$SSH_DIR" -name "*.pub" -type f | while read -r pub_file; do
    if [ -f "$pub_file" ]; then
        echo "--- $(basename "$pub_file") ---"
        cat "$pub_file"
        echo ""
    fi
done

# 显示SSH配置内容（如果存在）
if [ -f "$SSH_DIR/config" ]; then
    echo "=== SSH配置内容 ==="
    cat "$SSH_DIR/config"
    echo ""
fi

# 测试SSH连接（可选）
if [ $success_count -gt 0 ]; then
    if [ -t 0 ]; then
        # 标准输入是终端
        read -p "是否测试SSH连接到github.com？(y/n): " test_ssh
    else
        # 通过管道执行，从/dev/tty读取
        read -p "是否测试SSH连接到github.com？(y/n): " test_ssh < /dev/tty
    fi
    
    if [ "$test_ssh" = "y" ] || [ "$test_ssh" = "Y" ]; then
        echo "测试连接中..."
        ssh -T git@github.com
    fi
fi

echo ""
echo "💡 下一步操作："
echo "1. 将上面的公钥内容添加到相应的服务器:"
echo "   - GitHub: Settings → SSH and GPG keys → New SSH key"
echo "   - GitLab: User Settings → SSH Keys"
echo "   - 其他服务器: 添加到 ~/.ssh/authorized_keys"
echo "2. 测试连接: ssh -T git@github.com (或其他服务器)"
echo "3. 开始使用SSH进行操作"

if [ -f "$SSH_DIR/config" ]; then
    echo "4. SSH配置文件已安装，可以使用配置的主机别名"
fi
