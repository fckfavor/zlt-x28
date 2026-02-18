#!/bin/sh

# =============================
# BINARY INSTALLER 
# ZLT X28 - OpenWrt / BusyBox
# =============================

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
TEMP_DIR="/tmp/zlt-install"
GITHUB_ZIP="https://github.com/fckfavor/zlt-x28/archive/refs/heads/main.zip"
BINARY_SUBPATH="zlt-x28-main/binaries"

# Global binary listesi
BINARIES=""

print_green()  { echo -e "${GREEN}$1${NC}"; }
print_red()    { echo -e "${RED}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_blue()   { echo -e "${BLUE}$1${NC}"; }

# ---------- Root Kontrolü ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_red "Hata: Root yetkisi gerekli!"
        exit 1
    fi
}

# ---------- Dizin Oluştur ----------
create_dirs() {
    mkdir -p "$DATA_DIR"
    mkdir -p "$TEMP_DIR"
}

# ---------- ZIP İndir ----------
download_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"

    print_blue "▶ Repo ZIP indiriliyor..."

    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$GITHUB_ZIP" -O "$ZIP_FILE" 2>&1 || \
        wget -q "$GITHUB_ZIP" -O "$ZIP_FILE" 2>&1
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$ZIP_FILE" "$GITHUB_ZIP"
    else
        print_red "wget veya curl bulunamadı!"
        return 1
    fi

    if [ ! -f "$ZIP_FILE" ] || [ ! -s "$ZIP_FILE" ]; then
        print_red "İndirme başarısız!"
        return 1
    fi

    SIZE=$(ls -l "$ZIP_FILE" | awk '{print $5}')
    print_green "✓ İndirildi: $SIZE bytes"
    return 0
}

# ---------- ZIP Aç ----------
extract_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"

    print_blue "▶ ZIP açılıyor..."
    cd "$TEMP_DIR" || return 1

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$ZIP_FILE"
    elif busybox unzip "$ZIP_FILE" >/dev/null 2>&1; then
        :
    elif command -v tar >/dev/null 2>&1; then
        tar -xf "$ZIP_FILE" 2>/dev/null
    else
        print_red "ZIP açma aracı bulunamadı!"
        return 1
    fi

    if [ ! -d "$TEMP_DIR/zlt-x28-main" ]; then
        print_red "Extraction başarısız!"
        return 1
    fi

    print_green "✓ ZIP açıldı"
    return 0
}

# ---------- Binary Listele (GLOBAL set) ----------
load_binaries() {
    SOURCE_DIR="$TEMP_DIR/$BINARY_SUBPATH"

    if [ ! -d "$SOURCE_DIR" ]; then
        print_red "Binary dizini bulunamadı: $SOURCE_DIR"
        return 1
    fi

    # uhttpd'yi listeye dahil etme (luci-install.sh yönetir)
    BINARIES=$(ls -1 "$SOURCE_DIR" 2>/dev/null | grep -v '^uhttpd$' | grep -v '^$')

    if [ -z "$BINARIES" ]; then
        print_red "Binary bulunamadı!"
        return 1
    fi

    COUNT=$(echo "$BINARIES" | wc -l)
    print_green "✓ $COUNT binary bulundu"
    return 0
}

# ---------- Binary Kurulu mu? ----------
binary_exists() {
    BIN="$1"
    [ -f "$DATA_DIR/$BIN" ] && [ -x "$DATA_DIR/$BIN" ]
}

# ---------- Tek Binary Kur ----------
install_binary() {
    BINARY_NAME="$1"
    SOURCE="$TEMP_DIR/$BINARY_SUBPATH/$BINARY_NAME"
    DEST="$DATA_DIR/$BINARY_NAME"

    if [ ! -f "$SOURCE" ]; then
        print_red "Kaynak bulunamadı: $SOURCE"
        return 1
    fi

    if binary_exists "$BINARY_NAME"; then
        LOCAL_SIZE=$(ls -l "$DEST" | awk '{print $5}')
        SOURCE_SIZE=$(ls -l "$SOURCE" | awk '{print $5}')
        print_yellow "⚠ $BINARY_NAME zaten kurulu (${LOCAL_SIZE}b → ${SOURCE_SIZE}b)"
        printf "Üzerine yaz? [y/N]: "
        read ans
        case "$ans" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi

    cp "$SOURCE" "$DEST"
    chmod +x "$DEST"
    ln -sf "$DEST" "/usr/bin/$BINARY_NAME" 2>/dev/null

    SIZE=$(ls -l "$DEST" | awk '{print $5}')
    print_green "✓ $BINARY_NAME kuruldu (${SIZE}b)"
}

# ---------- Tümünü Kur ----------
install_all() {
    for bin in $BINARIES; do
        echo ""
        install_binary "$bin"
    done
    print_green "✓ Tüm binary'ler kuruldu!"
}

# ---------- Temizlik ----------
cleanup() {
    rm -rf "$TEMP_DIR"
    print_green "✓ Geçici dosyalar temizlendi"
}

# ---------- Menü ----------
show_menu() {
    clear
    echo "============================================"
    echo "   BINARY INSTALLER v4.0 — ZLT X28"
    echo "============================================"

    TOTAL=0
    INSTALLED=0
    BIN_LIST=""

    for bin in $BINARIES; do
        TOTAL=$((TOTAL + 1))
        if binary_exists "$bin"; then
            INSTALLED=$((INSTALLED + 1))
            STATUS="${GREEN}[✓]${NC}"
        else
            STATUS="${RED}[ ]${NC}"
        fi
        BIN_LIST="$BIN_LIST $bin"
        printf "  %2d) %-20s %b\n" "$TOTAL" "$bin" "$STATUS"
    done

    echo "--------------------------------------------"
    INSTALL_ALL_NUM=$((TOTAL + 1))
    EXIT_NUM=$((TOTAL + 2))
    printf "  %2d) Tümünü Kur\n" "$INSTALL_ALL_NUM"
    printf "  %2d) Temizle ve Çık\n" "$EXIT_NUM"
    echo "   0) Çıkış"
    echo "============================================"
    echo -e "  Kurulu: ${GREEN}$INSTALLED${NC}/$TOTAL"
    echo "============================================"
    printf "Seçiminiz [0-$EXIT_NUM]: "
    read choice

    if [ "$choice" = "0" ]; then
        cleanup
        print_green "Güle güle!"
        exit 0
    elif [ "$choice" = "$INSTALL_ALL_NUM" ]; then
        install_all
    elif [ "$choice" = "$EXIT_NUM" ]; then
        cleanup
        exit 0
    elif echo "$choice" | grep -qE '^[0-9]+$'; then
        if [ "$choice" -ge 1 ] && [ "$choice" -le "$TOTAL" ]; then
            j=1
            for bin in $BINARIES; do
                if [ "$j" = "$choice" ]; then
                    install_binary "$bin"
                    break
                fi
                j=$((j + 1))
            done
        else
            print_red "Geçersiz seçim!"
        fi
    else
        print_red "Geçersiz seçim!"
    fi
}

# ---------- Main ----------
main() {
    check_root
    create_dirs

    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║   ADIM 1/3 → ZIP İndiriliyor        ║"
    print_blue "╚══════════════════════════════════════╝"
    download_zip || exit 1

    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║   ADIM 2/3 → ZIP Açılıyor           ║"
    print_blue "╚══════════════════════════════════════╝"
    extract_zip || exit 1

    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║   ADIM 3/3 → Binary'ler Listeleniyor║"
    print_blue "╚══════════════════════════════════════╝"
    load_binaries || exit 1

    echo ""
    print_green "✓ Hazır! Binary kurulumuna geçiliyor..."
    echo ""
    sleep 1

    while true; do
        show_menu
        echo ""
        print_yellow "Devam için Enter..."
        read dummy
    done
}

main
