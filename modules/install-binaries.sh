#!/bin/sh

# =============================
# TOOL.SH - OpenWrt / BusyBox Installer
# =============================

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
GITHUB_REPO="https://github.com/fckfavor/zlt-x28"
BINARY_PATH="binaries"

# ---------- ROOT CHECK ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "${RED}Root olmalısın!${NC}"
        exit 1
    fi
}

# ---------- Gizli Binaries Dizin ----------
ensure_data_dir() {
    if [ ! -d "$DATA_DIR" ]; then
        echo "Gizli binary dizini oluşturuluyor: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    fi
}

# ---------- GitHub Binaries Listeleme ----------
fetch_binaries() {
    echo "Güncel binaryler çekiliyor..."
    FILES=$(curl -s "https://api.github.com/repos/fckfavor/zlt-x28/contents/$BINARY_PATH" | grep '"name":' | awk -F '"' '{print $4}')
    BINARIES=""
    for f in $FILES; do
        BINARIES="$BINARIES $f"
    done
}

# ---------- BusyBox Handling ----------
handle_busybox() {
    BUSYBOX_PATH=$(which busybox 2>/dev/null)
    if [ -n "$BUSYBOX_PATH" ]; then
        echo "Eski busybox bulundu: $BUSYBOX_PATH"
        mv "$BUSYBOX_PATH" "${BUSYBOX_PATH}2"
        echo "Eski busybox taşındı → ${BUSYBOX_PATH}2"
        TEMP_BUSYBOX="busybox2"
    else
        TEMP_BUSYBOX="busybox"
    fi

    echo "Yeni busybox indiriliyor..."
    curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/busybox" -o "$DATA_DIR/busybox"

    # Tek seferde tüm chmod işlemi
    chmod +x "$DATA_DIR"/*

    # Linkleme
    ln -sf "$DATA_DIR/busybox" "/usr/bin/busybox"
    echo "Yeni busybox kuruldu ve linklendi."
}

# ---------- Binary Kurulum ----------
install_binary() {
    BINARY_NAME="$1"

    if [ "$BINARY_NAME" = "busybox" ]; then
        handle_busybox
        return
    fi

    echo "Kuruluyor: $BINARY_NAME → $DATA_DIR"
    curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/$BINARY_NAME" -o "$DATA_DIR/$BINARY_NAME"

    # Tüm binaryler için tek seferde chmod
    chmod +x "$DATA_DIR"/*

    # Symlink
    ln -sf "$DATA_DIR/$BINARY_NAME" "/usr/bin/$BINARY_NAME"
    echo "${GREEN}$BINARY_NAME kuruldu!${NC}"
}

install_all_binaries() {
    for b in $BINARIES; do
        install_binary "$b"
    done
}

# ---------- Menü ----------
show_menu() {
    echo "====== Binaries Seçimi ======"
    i=1
    for f in $BINARIES; do
        echo "$i) $f"
        i=$((i+1))
    done
    echo "$i) Hepsini Kur"
    echo "0) Çıkış"
    printf "Seçiminiz: "
    read choice

    if [ "$choice" -eq 0 ]; then
        exit 0
    elif [ "$choice" -eq "$i" ]; then
        install_all_binaries
    else
        j=1
        for f in $BINARIES; do
            if [ "$j" -eq "$choice" ]; then
                install_binary "$f"
                break
            fi
            j=$((j+1))
        done
    fi
}

# ---------- MAIN ----------
check_root
ensure_data_dir
fetch_binaries

while true; do
    show_menu
    echo "Devam etmek için enter..."
    read dummy
done
