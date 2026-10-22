#!/usr/bin/env bash
# ==============================================================================
# IMYBinManager macOS 客户端打包与分发归档脚本
# ==============================================================================
# 功能：
#   1. 以 Release 配置编译 IMYBinManager 可执行文件
#   2. 构建标准 macOS .app Bundle 目录结构与完整元数据 (Info.plist / PkgInfo)
#   3. 执行 Ad-hoc (或指定 Developer ID) 代码签名以支持本地无障碍运行
#   4. 自动制作 ZIP 归档包和 DMG 磁盘映像并输出 SHA-256 校验和
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/dist"
APP_NAME="IMYBinManager"
BUNDLE_ID="org.imybin.IMYBinManager"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

# 默认参数
VERSION="1.0.0"
APP_ONLY=false
CREATE_DMG=true
SIGNING_IDENTITY="${SIGNING_IDENTITY:-"-"}" # 默认采用 Ad-hoc 本地签名

# 帮助信息
show_help() {
    cat <<EOF
用法: $(basename "$0") [选项]

将 IMYBinManager 打包为 macOS 应用程序并生成分发产物。

选项:
  -v, --version <版本号>   设置 App 版本号 (默认: $VERSION)
  --app-only              仅生成 .app 并签名，跳过 ZIP 与 DMG 归档制作
  --no-dmg                跳过生成 .dmg 镜像 (仅生成 .app 和 .zip)
  --sign-identity <标识>  指定代码签名身份 (默认: "-", 即 Ad-hoc 签名)
  -h, --help              显示此帮助信息

示例:
  ./$(basename "$0")                     # 完整打包 (.app + .zip + .dmg)
  ./$(basename "$0") -v 1.2.0           # 指定版本打包
  ./$(basename "$0") --app-only         # 快速本地调试打包 (仅 .app)
EOF
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        --app-only)
            APP_ONLY=true
            shift
            ;;
        --no-dmg)
            CREATE_DMG=false
            shift
            ;;
        --sign-identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "错误: 未知参数 '$1'" >&2
            show_help
            exit 1
            ;;
    esac
done

echo "=================================================="
echo "  IMYBinManager 打包分发流水线"
echo "  版本:    ${VERSION}"
echo "  签名:    ${SIGNING_IDENTITY}"
echo "  目标:    ${BUILD_DIR}"
echo "=================================================="

# 1. 编译 Release 二进制文件
echo "==> [1/4] 编译 Release 二进制文件..."
cd "${PROJECT_DIR}"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -f "${BINARY_PATH}" ]]; then
    echo "错误: 未找到编译后的二进制文件: ${BINARY_PATH}" >&2
    exit 1
fi

# 2. 构造 .app Bundle 目录结构
echo "==> [2/4] 构建 ${APP_NAME}.app 包结构..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 生成 PkgInfo
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 生成 Info.plist
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>IMY Bin Manager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 3. 代码签名
echo "==> [3/4] 执行代码签名 (Identity: ${SIGNING_IDENTITY})..."
codesign --force --deep --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

if [[ "${APP_ONLY}" == true ]]; then
    echo "==> 打包完成 (跳过归档制作)!"
    echo "  App 路径: ${APP_BUNDLE}"
    exit 0
fi

# 4. 创建归档分发物 (.zip & .dmg)
echo "==> [4/4] 生成分发归档与校验码..."
cd "${BUILD_DIR}"

# 制作 ZIP 归档
ZIP_FILE="${APP_NAME}.zip"
zip -qry "${ZIP_FILE}" "${APP_NAME}.app"
SHA256_ZIP=$(shasum -a 256 "${ZIP_FILE}" | awk '{print $1}')

# 制作 DMG 镜像 (如果可用且未禁用)
DMG_FILE="${APP_NAME}.dmg"
if [[ "${CREATE_DMG}" == true ]] && command -v hdiutil >/dev/null 2>&1; then
    hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_NAME}.app" -ov -format UDZO "${DMG_FILE}" >/dev/null
    SHA256_DMG=$(shasum -a 256 "${DMG_FILE}" | awk '{print $1}')
fi

echo "=================================================="
echo "  打包与归档完成！产物列表："
echo "=================================================="
echo "  [App] ${APP_BUNDLE}"
echo "  [ZIP] ${BUILD_DIR}/${ZIP_FILE}"
echo "        SHA-256: ${SHA256_ZIP}"
if [[ -f "${BUILD_DIR}/${DMG_FILE}" ]]; then
    echo "  [DMG] ${BUILD_DIR}/${DMG_FILE}"
    echo "        SHA-256: ${SHA256_DMG}"
fi
echo "=================================================="
