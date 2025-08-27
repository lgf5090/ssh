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

# 获取仓库中的文件列表（通过GitHub API或直接尝试常见文件）
declare -a FILES_TO_DOWNLOAD=()
declare -a ENCRYPTED_FILES=()
declare -a PUBLIC_KEYS=()

# 预定义可能的文件模式
POSSIBLE_PATTERNS=(
    "id_ed25519"
    "id_rsa" 
    "id_ecdsa"
    "config"
)

# 尝试下载各种可能的文件
echo "扫描和下载文件..."

# 下载config文件（如果存在）
echo "尝试下载 config..."
if curl -f -L -s "$RAW_BASE_URL/config" -o "config" 2>/dev/null; then
    echo "✅ 下载 config 成功"
    FILES_TO_DOWNLOAD+=("config")
else
    echo "⚠️  config 文件不存在，跳过"
fi

# 扫描加密的私钥文件和对应的公钥
for pattern in "${POSSIBLE_PATTERNS[@]}"; do
    encrypted_file="${pattern}.encrypted"
    pub_file="${pattern}.pub"
    
    echo "尝试下载 $encrypted_file..."
    if curl -f -L -s "$RAW_BASE_URL/$encrypted_file" -o "$encrypted_file" 2>/dev/null; then
        echo "✅ 下载 $encrypted_file 成功"
        ENCRYPTED_FILES+=("$encrypted_file")
        
        # 尝试下载对应的公钥
        echo "尝试下载 $pub_file..."
        if curl -f -L -s "$RAW_BASE_URL/$pub_file" -o "$pub_file" 2>/dev/null; then
            echo "✅ 下载 $pub_file 成功"
            PUBLIC_KEYS+=("$pub_file")
        else
            echo "⚠️  $pub_file 不存在，跳过"
        fi
    else
        echo "⚠️  $encrypted_file 不存在，跳过"
    fi
done

# 检查是否下载到任何文件
total_files=$((${#FILES_TO_DOWNLOAD[@]} + ${#ENCRYPTED_FILES[@]} + ${#PUBLIC_KEYS[@]}))
if [ $total_files -eq 0 ]; then
    echo "❌ 没有找到任何SSH配置文件！"
    echo "请检查仓库: $REPO_URL"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""
echo "📋 发现的文件："
echo "配置文件: ${FILES_TO_DOWNLOAD[*]:-无}"
echo "加密私钥: ${ENCRYPTED_FILES[*]:-无}"
echo "公钥文件: ${PUBLIC_KEYS[*]:-无}"
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

# 解密所有加密的私钥文件
success_count=0
for encrypted_file in "${ENCRYPTED_FILES[@]}"; do
    # 提取原始文件名（去掉.encrypted后缀）
    original_name="${encrypted_file%.encrypted}"
    
    echo "🔓 解密 $encrypted_file → $original_name"
    
    if openssl aes-256-cbc -d -salt -in "$encrypted_file" -out "$SSH_DIR/$original_name" -pass pass:"$password" 2>/dev/null; then
        echo "✅ $original_name 解密成功"
        chmod 600 "$SSH_DIR/$original_name"
        ((success_count++))
    else
        echo "❌ $original_name 解密失败！"
        rm -f "$SSH_DIR/$original_name"
    fi
done

# 复制公钥文件
for pub_file in "${PUBLIC_KEYS[@]}"; do
    echo "📄 复制公钥: $pub_file"
    cp "$pub_file" "$SSH_DIR/"
    chmod 644 "$SSH_DIR/$pub_file"
done

# 复制配置文件
for config_file in "${FILES_TO_DOWNLOAD[@]}"; do
    if [ "$config_file" = "config" ]; then
        echo "⚙️  复制SSH配置: $config_file"
        cp "$config_file" "$SSH_DIR/"
        chmod 600 "$SSH_DIR/$config_file"
    fi
done

# 设置SSH目录权限
chmod 700 "$SSH_DIR"

# 清理临时文件
rm -rf "$TEMP_DIR"

echo ""
echo "✅ 安装完成！"
echo "📁 SSH目录: $SSH_DIR/"
echo "🔐 解密成功的私钥: $success_count 个"
echo "🔓 安装的公钥: ${#PUBLIC_KEYS[@]} 个"
echo "⚙️  配置文件: ${#FILES_TO_DOWNLOAD[@]} 个"
echo ""

# 显示SSH目录内容
echo "=== SSH目录内容 ==="
ls -la "$SSH_DIR/"
echo ""

# 显示所有公钥内容
if [ ${#PUBLIC_KEYS[@]} -gt 0 ]; then
    echo "=== 公钥内容 ==="
    for pub_file in "${PUBLIC_KEYS[@]}"; do
        echo "--- $pub_file ---"
        cat "$SSH_DIR/$pub_file"
        echo ""
    done
fi

# 显示SSH配置内容（如果存在）
if [ -f "$SSH_DIR/config" ]; then
    echo "=== SSH配置内容 ==="
    cat "$SSH_DIR/config"
    echo ""
fi

# 测试SSH连接（可选）
if [ ${#ENCRYPTED_FILES[@]} -gt 0 ]; then
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
