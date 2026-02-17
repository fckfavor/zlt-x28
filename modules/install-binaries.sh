#!/bin/sh

# =============================
# TOOL.SH - OpenWrt / BusyBox Installer
# =============================

# Renk tanımlamaları (OpenWrt'de echo -e gerektirebilir)
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
GITHUB_REPO="https://github.com/fckfavor/zlt-x28"
BINARY_PATH="binaries"

# ---------- Echo helper ----------
print_green() {
    echo -e "${GREEN}$1${NC}"
}

print_red() {
    echo -e "${RED}$1${NC}"
}

# ---------- ROOT CHECK ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_red "Root olmalısın!"
        exit 1
    fi
}

# ---------- Gizli Binaries Dizin ----------
ensure_data_dir() {
    if [ ! -d "$DATA_DIR" ]; then
        print_green "Gizli binary dizini oluşturuluyor: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    fi
}

# ---------- GitHub Binaries Listeleme ----------
fetch_binaries() {
    print_green "Güncel binaryler çekiliyor..."
    
    # GitHub API'den dosya listesini al
    BINARIES=$(curl -s "https://api.github.com/repos/fckfavor/zlt-x28/contents/$BINARY_PATH" | grep '"name":' | cut -d '"' -f 4)
    
    if [ -z "$BINARIES" ]; then
        print_red "Binary listesi alınamadı! GitHub'a erişim kontrol edin."
        exit 1
    fi
    
    print_green "Bulunan binaryler: $BINARIES"
}

# ---------- BusyBox Handling ----------
handle_busybox() {
    BUSYBOX_PATH=$(which busybox 2>/dev/null)
    
    if [ -n "$BUSYBOX_PATH" ] && [ -f "$BUSYBOX_PATH" ]; then
        print_green "Eski busybox bulundu: $BUSYBOX_PATH"
        mv "$BUSYBOX_PATH" "${BUSYBOX_PATH}.backup"
        print_green "Eski busybox taşındı → ${BUSYBOX_PATH}.backup"
    fi

    print_green "Yeni busybox indiriliyor..."
    if ! curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/busybox" -o "$DATA_DIR/busybox"; then
        print_red "Busybox indirilemedi!"
        return 1
    fi

    chmod +x "$DATA_DIR/busybox"
    
    # Linkleme
    if [ -L "/usr/bin/busybox" ]; then
        rm -f "/usr/bin/busybox"
    fi
    ln -sf "$DATA_DIR/busybox" "/usr/bin/busybox"
    
    print_green "Yeni busybox kuruldu ve linklendi."
}

# ---------- Binary Kurulum ----------
install_binary() {
    BINARY_NAME="$1"

    if [ "$BINARY_NAME" = "busybox" ]; then
        handle_busybox
        return
    fi

    print_green "Kuruluyor: $BINARY_NAME → $DATA_DIR"
    
    if ! curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/$BINARY_NAME" -o "$DATA_DIR/$BINARY_NAME"; then
        print_red "$BINARY_NAME indirilemedi!"
        return 1
    fi

    chmod +x "$DATA_DIR/$BINARY_NAME"

    # Symlink (eski symlink varsa sil)
    if [ -L "/usr/bin/$BINARY_NAME" ]; then
        rm -f "/usr/bin/$BINARY_NAME"
    fi
    ln -sf "$DATA_DIR/$BINARY_NAME" "/usr/bin/$BINARY_NAME"
    
    print_green "$BINARY_NAME kuruldu!"
}

install_all_binaries() {
    for b in $BINARIES; do
        install_binary "$b"
    done
}

# ---------- Menü ----------
show_menu() {
    clear
    echo "===================================="
    echo "     BINARY INSTALLER v1.0"
    echo "===================================="
    
    # Binaryleri diziye çevir
    set -- $BINARIES
    count=$#
    
    i=1
    for f in $BINARIES; do
        if [ -f "$DATA_DIR/$f" ]; then
            echo "$i) $f (${GREEN}kurulu${NC})"
        else
            echo "$i) $f"
        fi
        i=$((i+1))
    done
    
    echo "$i) Hepsini Kur"
    echo "0) Çıkış"
    echo "===================================="
    printf "Seçiminiz: "
    read choice

    case "$choice" in
        0) exit 0 ;;
        $i) install_all_binaries ;;
        *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                j=1
                for f in $BINARIES; do
                    if [ "$j" -eq "$choice" ]; then
                        install_binary "$f"
                        break
                    fi
                    j=$((j+1))
                done
            else
                print_red "Geçersiz seçim!"
            fi
            ;;
    esac
}

# ---------- Ana fonksiyon ----------
main() {
    check_root
    ensure_data_dir
    fetch_binaries

    while true; do
        show_menu
        echo ""
        echo "Devam etmek için Enter'a basın..."
        read dummy
    done
}

# ---------- Script'i başlat ----------
main
