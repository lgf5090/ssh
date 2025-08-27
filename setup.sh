#!/bin/bash

# setup.sh
# SSH密钥解密和设置脚本

# set -e

# 默认Git仓库地址
DEFAULT_REPO="https://github.com/lgf5090/ssh.git"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -l, --local    本地模式：解密当前目录中的 .encrypted 文件"
    echo "  -r, --repo     指定Git仓库地址 (默认: $DEFAULT_REPO)"
    echo "  -h, --help     显示此帮助信息"
    echo ""
    echo "说明:"
    echo "  默认模式: 从指定的Git仓库下载加密文件并解密到 ~/.ssh/"
    echo "  本地模式(-l): 解密当前目录中的加密文件到 ~/.ssh/"
    echo "  如果 ~/.ssh/ 目录不存在会自动创建"
    echo "  解密后的文件会自动设置正确的权限"
}

# 获取用户密码
get_password() {
    echo -n "请输入解密密码: "
    read -s password
    echo
    
    if [ -z "$password" ]; then
        echo -e "${RED}错误: 密码不能为空${NC}"
        exit 1
    fi
}

# 解密文件
decrypt_file() {
    local encrypted_file="$1"
    local decrypted_file="$2"
    
    echo "正在解密 $encrypted_file -> $decrypted_file"
    
    # 尝试解密
    if openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -in "$encrypted_file" -out "$decrypted_file" -pass pass:"$password" 2>/dev/null; then
        echo -e "${GREEN}✓ 成功解密: $decrypted_file${NC}"
        return 0
    else
        echo -e "${RED}✗ 解密失败: $encrypted_file${NC}"
        rm -f "$decrypted_file"  # 清理可能的不完整文件
        return 1
    fi
}

# 设置SSH文件权限
set_ssh_permissions() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # 检查是否为私钥文件（不以.pub结尾）
    if [[ "$filename" != *.pub ]]; then
        # 私钥文件设置为600权限
        chmod 600 "$file_path"
        echo -e "${BLUE}✓ 设置私钥权限 600: $filename${NC}"
    else
        # 公钥文件设置为644权限
        chmod 644 "$file_path"
        echo -e "${BLUE}✓ 设置公钥权限 644: $filename${NC}"
    fi
}

# 创建.ssh目录
create_ssh_directory() {
    local ssh_dir="$HOME/.ssh"
    
    if [ ! -d "$ssh_dir" ]; then
        echo "创建 .ssh 目录: $ssh_dir"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        echo -e "${GREEN}✓ .ssh 目录创建成功${NC}"
    else
        echo -e "${BLUE}✓ .ssh 目录已存在${NC}"
    fi
    
    # 确保.ssh目录有正确的权限
    chmod 700 "$ssh_dir"
}

# 获取原始文件名（去除.encrypted后缀）
get_original_filename() {
    local encrypted_file="$1"
    echo "${encrypted_file%.encrypted}"
}

# 检查是否为SSH相关文件
is_ssh_related_file() {
    local filename="$1"
    
    # SSH密钥文件通常的命名模式
    if [[ "$filename" == id_* ]] || \
       [[ "$filename" == *_rsa* ]] || \
       [[ "$filename" == *_ed25519* ]] || \
       [[ "$filename" == *_ecdsa* ]] || \
       [[ "$filename" == authorized_keys ]] || \
       [[ "$filename" == known_hosts ]] || \
       [[ "$filename" == config ]]; then
        return 0
    fi
    
    return 1
}

# 从Git仓库下载文件
download_from_repo() {
    local repo_url="$1"
    local temp_dir=$(mktemp -d)
    
    echo -e "${GREEN}=== 从Git仓库下载加密文件 ===${NC}"
    echo "仓库地址: $repo_url"
    echo "临时目录: $temp_dir"
    
    # 克隆仓库
    if git clone "$repo_url" "$temp_dir" 2>/dev/null; then
        echo -e "${GREEN}✓ 成功克隆仓库${NC}"
    else
        echo -e "${RED}✗ 克隆仓库失败: $repo_url${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 检查是否有加密文件
    local encrypted_files=$(find "$temp_dir" -name "*.encrypted" -type f 2>/dev/null || true)
    if [ -z "$encrypted_files" ]; then
        echo -e "${YELLOW}仓库中没有找到 .encrypted 文件${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo "找到加密文件:"
    find "$temp_dir" -name "*.encrypted" -type f | while read file; do
        echo "  - $(basename "$file")"
    done
    
    # 复制加密文件到当前目录
    find "$temp_dir" -name "*.encrypted" -type f -exec cp {} . \;
    echo -e "${GREEN}✓ 加密文件已复制到当前目录${NC}"
    
    # 清理临时目录
    rm -rf "$temp_dir"
}

# 主解密流程（本地模式）
decrypt_local_files() {
    echo -e "${GREEN}=== SSH密钥解密和设置（本地模式） ===${NC}"
    
    # 获取密码
    get_password
    
    # 创建.ssh目录
    create_ssh_directory
    
    local ssh_dir="$HOME/.ssh"
    local files_found=false
    local decrypted_count=0
    local failed_count=0
    
    # 先列出所有找到的加密文件
    echo "扫描加密文件..."
    local encrypted_files=(*.encrypted)
    if [ "${encrypted_files[0]}" = "*.encrypted" ]; then
        echo -e "${YELLOW}在当前目录中没有找到 .encrypted 文件${NC}"
        return
    fi
    
    echo "找到以下加密文件:"
    for file in "${encrypted_files[@]}"; do
        echo "  - $file"
    done
    echo ""
    
    # 处理每个加密文件
    for encrypted_file in "${encrypted_files[@]}"; do
        # 检查文件是否存在
        if [ ! -f "$encrypted_file" ]; then
            echo -e "${YELLOW}警告: 文件不存在: $encrypted_file${NC}"
            continue
        fi
        
        files_found=true
        
        # 获取原始文件名
        local original_filename=$(get_original_filename "$encrypted_file")
        local target_file="$ssh_dir/$original_filename"
        
        echo "=========================================="
        echo "处理文件: $encrypted_file"
        echo "目标位置: $target_file"
        
        # 检查目标文件是否已存在
        if [ -f "$target_file" ]; then
            echo -n -e "${YELLOW}目标文件已存在，是否覆盖? (y/N): ${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}跳过: $encrypted_file${NC}"
                echo ""
                continue
            fi
        fi
        
        # 解密文件
        if decrypt_file "$encrypted_file" "$target_file"; then
            # 设置正确的权限
            set_ssh_permissions "$target_file"
            ((decrypted_count++))
            
            # 显示文件信息
            echo -e "${BLUE}文件信息: $(ls -la "$target_file")${NC}"
            echo -e "${GREEN}✓ 成功处理: $encrypted_file${NC}"
        else
            ((failed_count++))
            echo -e "${RED}✗ 解密失败: $encrypted_file (可能是密码错误或文件损坏)${NC}"
        fi
        echo ""
    done
    
    echo ""
    echo -e "${GREEN}=== 处理完成 ===${NC}"
    
    if [ "$files_found" = false ]; then
        echo -e "${YELLOW}在当前目录中没有找到 .encrypted 文件${NC}"
    else
        echo "处理结果:"
        echo "  ✓ 成功解密: $decrypted_count 个文件"
        if [ $failed_count -gt 0 ]; then
            echo "  ✗ 解密失败: $failed_count 个文件"
        fi
        
        if [ $decrypted_count -gt 0 ]; then
            echo ""
            echo -e "${GREEN}SSH文件已成功解密并放置到 ~/.ssh/ 目录${NC}"
            echo -e "${BLUE}您现在可以使用这些SSH密钥了${NC}"
            
            # 显示.ssh目录内容
            echo ""
            echo "~/.ssh/ 目录内容:"
            ls -la "$ssh_dir"
        fi
    fi
}

# 主解密流程（远程模式）
decrypt_remote_files() {
    local repo_url="$1"
    
    echo -e "${GREEN}=== SSH密钥解密和设置（远程模式） ===${NC}"
    
    # 下载文件
    download_from_repo "$repo_url"
    
    # 解密本地文件
    decrypt_local_files
    
    # 清理下载的加密文件
    echo ""
    echo -e "${BLUE}清理下载的加密文件...${NC}"
    rm -f *.encrypted
    echo -e "${GREEN}✓ 清理完成${NC}"
}

# 检查依赖
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}错误: 未找到 openssl 命令${NC}"
        exit 1
    fi
}

# 检查Git依赖（仅在需要时检查）
check_git_dependency() {
    if ! command -v git &> /dev/null; then
        echo -e "${RED}错误: 未找到 git 命令，远程模式需要git${NC}"
        exit 1
    fi
}

# 主函数
main() {
    local mode="remote"  # 默认为远程模式
    local repo_url="$DEFAULT_REPO"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--local)
                mode="local"
                shift
                ;;
            -r|--repo)
                repo_url="$2"
                if [ -z "$repo_url" ]; then
                    echo -e "${RED}错误: -r 选项需要提供仓库地址${NC}"
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查基本依赖
    check_dependencies
    
    # 根据模式执行相应操作
    case $mode in
        "local")
            decrypt_local_files
            ;;
        "remote")
            check_git_dependency
            decrypt_remote_files "$repo_url"
            ;;
        *)
            echo -e "${RED}错误: 未知模式 $mode${NC}"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
