#!/bin/bash

# setup.sh - SSH密钥批量解密和安装脚本
echo "=== SSH密钥批量安装工具 v2.1 ==="
echo "仓库: https://github.com/lgf5090/ssh.git"

# 设置变量
SSH_DIR="$HOME/.ssh"
TEMP_DIR="/tmp/ssh-setup-$$"
RAW_BASE_URL="https://raw.githubusercontent.com/lgf5090/ssh/main"

# 检查依赖
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo "❌ 错误：openssl 未安装。"
        echo "请先安装openssl："
        echo "Ubuntu/Debian: sudo apt-get install openssl"
        echo "CentOS/RHEL: sudo yum install openssl"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo "❌ 错误：curl 未安装。"
        echo "请先安装curl"
        exit 1
    fi
    
    # 显示OpenSSL版本信息
    echo "OpenSSL版本: $(openssl version)"
}

# 获取密码
get_password() {
    if [ -t 0 ]; then
        # 标准输入是终端，直接读取
        read -sp "请输入解密密码: " password
        echo
    else
        # 标准输入被管道占用，从/dev/tty读取
        echo "检测到通过管道执行，请在终端中输入密码："
        read -sp "请输入解密密码: " password < /dev/tty
        echo
    fi
}

# 解密文件 - 修复版本
decrypt_file() {
    local encrypted_file="$1"
    local output_file="$2"
    local password="$3"
    
    echo "🔓 解密 $(basename "$encrypted_file") → $(basename "$output_file")"
    
    # 尝试多种解密方式，按优先级排序
    local methods=(
        # 方法1：兼容模式（与修复的加密脚本匹配）
        "openssl aes-256-cbc -d -salt -md md5 -in '$encrypted_file' -out '$output_file' -pass pass:'$password'"
        
        # 方法2：新版OpenSSL默认方式
        "openssl aes-256-cbc -d -pbkdf2 -salt -in '$encrypted_file' -out '$output_file' -pass pass:'$password'"
        
        # 方法3：旧版OpenSSL方式
        "openssl aes-256-cbc -d -salt -in '$encrypted_file' -out '$output_file' -pass pass:'$password'"
        
        # 方法4：指定旧的摘要算法
        "openssl aes-256-cbc -d -salt -md sha256 -in '$encrypted_file' -out '$output_file' -pass pass:'$password'"
    )
    
    for i in "${!methods[@]}"; do
        local method="${methods[$i]}"
        echo "  尝试方法 $((i+1))/4..."
        
        # 清理之前的失败输出
        rm -f "$output_file"
        
        if eval "$method" 2>/dev/null; then
            # 验证解密结果
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                echo "✅ $(basename "$output_file") 解密成功 (方法 $((i+1)))"
                return 0
            fi
        fi
    done
    
    echo "❌ $(basename "$output_file") 所有解密方法都失败了！"
    rm -f "$output_file"
    return 1
}

# 主函数
main() {
    check_dependencies
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    echo "当前工作目录: $(pwd)"
    echo "开始下载SSH配置文件..."
    
    # 获取加密文件列表
    declare -a ENCRYPTED_FILES=()
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
    for encrypted_pattern in "${POSSIBLE_ENCRYPTED_PATTERNS[@]}"; do
        echo "尝试下载 $encrypted_pattern..."
        if curl -f -L -s "$RAW_BASE_URL/$encrypted_pattern" -o "$encrypted_pattern" 2>/dev/null; then
            # 验证下载的文件不为空
            if [ -s "$encrypted_pattern" ]; then
                echo "✅ 下载 $encrypted_pattern 成功"
                ENCRYPTED_FILES+=("$encrypted_pattern")
            else
                echo "⚠️  $encrypted_pattern 文件为空，跳过"
                rm -f "$encrypted_pattern"
            fi
        else
            echo "⚠️  $encrypted_pattern 不存在，跳过"
        fi
    done
    
    if [ ${#ENCRYPTED_FILES[@]} -eq 0 ]; then
        echo "❌ 没有找到任何加密的SSH配置文件！"
        echo "请检查："
        echo "1. 网络连接是否正常"
        echo "2. GitHub仓库是否存在"
        echo "3. 加密文件是否已上传到仓库"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    echo ""
    echo "📋 发现的加密文件："
    printf '  %s\n' "${ENCRYPTED_FILES[@]}"
    echo ""
    
    # 创建SSH目录
    mkdir -p "$SSH_DIR"
    
    # 获取密码
    get_password
    
    if [ -z "$password" ]; then
        echo "❌ 密码不能为空！"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 解密文件
    success_count=0
    failed_files=()
    
    for encrypted_file in "${ENCRYPTED_FILES[@]}"; do
        original_name="${encrypted_file%.encrypted}"
        
        if decrypt_file "$encrypted_file" "$SSH_DIR/$original_name" "$password"; then
            # 设置正确的权限
            if [[ "$original_name" == *.pub ]]; then
                chmod 644 "$SSH_DIR/$original_name"
                echo "  设置公钥权限: 644"
            elif [[ "$original_name" == "config" ]]; then
                chmod 600 "$SSH_DIR/$original_name"
                echo "  设置配置文件权限: 600"
            else
                chmod 600 "$SSH_DIR/$original_name"
                echo "  设置私钥权限: 600"
            fi
            
            ((success_count++))
        else
            failed_files+=("$original_name")
            rm -f "$SSH_DIR/$original_name"
        fi
        echo
    done
    
    # 设置SSH目录权限
    chmod 700 "$SSH_DIR"
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "=== 安装结果 ==="
    echo "✅ 成功解密: $success_count/${#ENCRYPTED_FILES[@]} 个文件"
    
    if [ ${#failed_files[@]} -gt 0 ]; then
        echo "❌ 解密失败的文件:"
        printf '  %s\n' "${failed_files[@]}"
        echo ""
        echo "💡 解密失败可能的原因："
        echo "1. 密码输入错误"
        echo "2. 文件在传输过程中损坏"
        echo "3. OpenSSL版本不兼容"
        echo "4. 加密文件格式不匹配"
    fi
    
    echo ""
    echo "📁 SSH目录: $SSH_DIR/"
    echo ""
    
    # 显示目录内容
    echo "=== SSH目录内容 ==="
    ls -la "$SSH_DIR/"
    echo ""
    
    if [ $success_count -gt 0 ]; then
        echo "🎉 SSH密钥安装完成！"
        
        # 检查是否有私钥，给出使用提示
        if ls "$SSH_DIR"/id_* 2>/dev/null | grep -v "\.pub$" >/dev/null; then
            echo ""
            echo "💡 使用提示："
            echo "测试SSH连接: ssh -T git@github.com"
            echo "查看密钥指纹: ssh-keygen -lf ~/.ssh/id_ed25519.pub"
        fi
    else
        echo "😞 没有成功解密任何文件，请检查密码是否正确"
        exit 1
    fi
}

# 执行主函数
main "$@"
