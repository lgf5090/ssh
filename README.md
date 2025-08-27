# SSH密钥一键安装

这个仓库提供预配置的SSH密钥，方便快速设置开发环境。

## 快速开始

### 方法一：直接下载运行（推荐）
```bash
# 下载并运行安装脚本
curl -s https://raw.githubusercontent.com/lgf5090/ssh/main/setup.sh | bash
```

### 方法二：手动下载运行
```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/lgf5090/ssh/main/setup.sh

# 给执行权限
chmod +x setup.sh

# 运行脚本
./setup.sh
```

## 功能特点
- ✅ 自动下载加密的SSH密钥
- ✅ 安全解密（AES-256加密）
- ✅ 自动设置正确的文件权限
- ✅ 显示公钥内容，方便添加到GitHub
- ✅ 可选测试连接

## 文件说明
- `id_ed25519.encrypted` - 加密的SSH私钥（AES-256）
- `id_ed25519.pub` - SSH公钥（明文）
- `setup.sh` - 一键安装脚本

## 安全提示
- 🔒 私钥使用强密码加密存储
- 🔐 只有知道密码才能解密使用
- 📁 自动设置安全的文件权限
- ⚠️ 请妥善保管解密密码

## 技术支持
如有问题，请提交Issue或联系维护者。
