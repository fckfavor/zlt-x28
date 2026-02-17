#!/bin/sh

# =============================
# BINARY INSTALLER FOR OpenWrt/BusyBox
# =============================

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
GITHUB_REPO="https://github.com/fckfavor/zlt-x28"
BINARY_PATH="binaries"

# ---------- Print Functions ----------
print_green() { echo -e "${GREEN}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_blue() { echo -e "${BLUE}$1${NC}"; }

# ---------- Progress Bar for wget (BusyBox friendly) ----------
download_with_progress() {
    URL="$1"
    OUTPUT="$2"
    FILENAME=$(basename "$OUTPUT")
    
    print_blue "Downloading: $FILENAME"
    
    # BusyBox wget supports -q (quiet) and -O (output)
    # Use -q to hide output but show progress with dots
    wget -O "$OUTPUT" "$URL" 2>&1 | while read line; do
        if echo "$line" | grep -q '%'; then
            # Extract percentage if available
            PERCENT=$(echo "$line" | grep -o '[0-9]\+%' | head -1)
            if [ -n "$PERCENT" ]; then
                printf "\r${BLUE}[%-10s${NC}] %s" "$(printf '#%.0s' $(seq 1 $(( ${PERCENT%\%} / 10 ))))" "$PERCENT"
            fi
        fi
    done
    
    if [ $? -eq 0 ] && [ -f "$OUTPUT" ]; then
        printf "\r${GREEN}[##########] 100%%${NC} - Complete!\n"
        return 0
    else
        printf "\r${RED}[##########] FAILED${NC}\n"
        return 1
    fi
}

# ---------- Alternative: Simple wget with dots ----------
simple_download() {
    URL="$1"
    OUTPUT="$2"
    
    print_blue "Downloading: $(basename "$OUTPUT")"
    wget -O "$OUTPUT" "$URL" 2>&1 | grep --line-buffered -o '[0-9]\+%' | while read pct; do
        printf "\rProgress: %s" "$pct"
    done
    
    if [ $? -eq 0 ] && [ -f "$OUTPUT" ]; then
        printf "\r${GREEN}Complete!             ${NC}\n"
        return 0
    else
        printf "\r${RED}Failed!${NC}\n"
        return 1
    fi
}

# ---------- Root Check ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_red "Error: Root privileges required!"
        print_yellow "Please run: sudo $0"
        exit 1
    fi
}

# ---------- Create Data Directory ----------
ensure_data_dir() {
    if [ ! -d "$DATA_DIR" ]; then
        print_yellow "Creating directory: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    fi
}

# ---------- Check if Binary Exists ----------
binary_exists() {
    BIN_NAME="$1"
    
    # Check in DATA_DIR
    if [ -f "$DATA_DIR/$BIN_NAME" ] && [ -x "$DATA_DIR/$BIN_NAME" ]; then
        return 0
    fi
    
    # Check in system PATH
    if command -v "$BIN_NAME" >/dev/null 2>&1; then
        # Check if it's our symlink
        if [ -L "/usr/bin/$BIN_NAME" ] && [ "$(readlink "/usr/bin/$BIN_NAME")" = "$DATA_DIR/$BIN_NAME" ]; then
            return 0
        fi
    fi
    
    return 1
}

# ---------- Get File Size ----------
get_file_size() {
    if [ -f "$1" ]; then
        ls -l "$1" | awk '{print $5}'
    else
        echo "0"
    fi
}

# ---------- Check Remote File Info ----------
check_remote_file() {
    BIN_NAME="$1"
    URL="$GITHUB_REPO/raw/main/$BINARY_PATH/$BIN_NAME"
    
    # Get remote file size using wget --spider
    SIZE=$(wget --spider "$URL" 2>&1 | grep "Length:" | awk '{print $2}' | cut -d'(' -f1)
    
    if [ -z "$SIZE" ]; then
        echo "Unknown"
    else
        echo "$SIZE"
    fi
}

# ---------- BusyBox Handling ----------
handle_busybox() {
    if binary_exists "busybox"; then
        print_yellow "✓ BusyBox already installed (version: $($DATA_DIR/busybox --help | head -1))"
        print_yellow "  Location: $DATA_DIR/busybox"
        
        printf "Reinstall? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi
    
    BUSYBOX_PATH=$(which busybox 2>/dev/null)
    if [ -n "$BUSYBOX_PATH" ] && [ -f "$BUSYBOX_PATH" ] && [ ! -L "$BUSYBOX_PATH" ]; then
        print_yellow "Backing up original busybox: $BUSYBOX_PATH → ${BUSYBOX_PATH}.backup"
        mv "$BUSYBOX_PATH" "${BUSYBOX_PATH}.backup"
    fi

    print_blue "Downloading BusyBox..."
    REMOTE_SIZE=$(check_remote_file "busybox")
    print_blue "Remote size: $REMOTE_SIZE bytes"
    
    # Try progress download, fallback to simple
    if command -v wget >/dev/null 2>&1; then
        download_with_progress "$GITHUB_REPO/raw/main/$BINARY_PATH/busybox" "$DATA_DIR/busybox"
    else
        curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/busybox" -o "$DATA_DIR/busybox"
    fi
    
    if [ $? -ne 0 ] || [ ! -f "$DATA_DIR/busybox" ]; then
        print_red "Failed to download BusyBox!"
        return 1
    fi
    
    chmod +x "$DATA_DIR/busybox"
    LOCAL_SIZE=$(get_file_size "$DATA_DIR/busybox")
    print_green "Downloaded: $LOCAL_SIZE bytes"
    
    # Create symlink
    if [ -L "/usr/bin/busybox" ]; then
        rm -f "/usr/bin/busybox"
    fi
    ln -sf "$DATA_DIR/busybox" "/usr/bin/busybox"
    
    print_green "✓ BusyBox installed successfully!"
    print_green "  Version: $($DATA_DIR/busybox --help | head -1)"
}

# ---------- Install Single Binary ----------
install_binary() {
    BINARY_NAME="$1"
    FORCE="$2"

    if [ "$BINARY_NAME" = "busybox" ]; then
        handle_busybox
        return
    fi

    # Check if already installed
    if [ "$FORCE" != "force" ] && binary_exists "$BINARY_NAME"; then
        print_yellow "✓ $BINARY_NAME already installed"
        if [ -f "$DATA_DIR/$BINARY_NAME" ]; then
            LOCAL_SIZE=$(get_file_size "$DATA_DIR/$BINARY_NAME")
            print_yellow "  Location: $DATA_DIR/$BINARY_NAME ($LOCAL_SIZE bytes)"
        fi
        printf "Reinstall? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi

    print_blue "Installing: $BINARY_NAME"
    REMOTE_SIZE=$(check_remote_file "$BINARY_NAME")
    print_blue "Remote size: $REMOTE_SIZE bytes"
    
    # Download with progress
    if command -v wget >/dev/null 2>&1; then
        download_with_progress "$GITHUB_REPO/raw/main/$BINARY_PATH/$BINARY_NAME" "$DATA_DIR/$BINARY_NAME"
    else
        curl -L "$GITHUB_REPO/raw/main/$BINARY_PATH/$BINARY_NAME" -o "$DATA_DIR/$BINARY_NAME"
    fi
    
    if [ $? -ne 0 ] || [ ! -f "$DATA_DIR/$BINARY_NAME" ]; then
        print_red "Failed to download $BINARY_NAME!"
        return 1
    fi

    chmod +x "$DATA_DIR/$BINARY_NAME"
    LOCAL_SIZE=$(get_file_size "$DATA_DIR/$BINARY_NAME")
    print_green "Downloaded: $LOCAL_SIZE bytes"

    # Create symlink
    if [ -L "/usr/bin/$BINARY_NAME" ]; then
        rm -f "/usr/bin/$BINARY_NAME"
    fi
    ln -sf "$DATA_DIR/$BINARY_NAME" "/usr/bin/$BINARY_NAME"
    
    print_green "✓ $BINARY_NAME installed successfully!"
}

# ---------- Install All Binaries ----------
install_all_binaries() {
    for b in $BINARIES; do
        echo ""
        install_binary "$b" "force"
    done
}

# ---------- Fetch Binaries List ----------
fetch_binaries() {
    print_blue "Fetching binary list from GitHub..."
    
    BINARIES=$(curl -s "https://api.github.com/repos/fckfavor/zlt-x28/contents/$BINARY_PATH" | grep '"name":' | cut -d '"' -f 4)
    
    if [ -z "$BINARIES" ]; then
        print_red "Failed to fetch binary list! Check internet connection."
        exit 1
    fi
    
    COUNT=$(echo "$BINARIES" | wc -w)
    print_green "Found $COUNT binaries available"
}

# ---------- Show Menu ----------
show_menu() {
    clear
    echo "============================================"
    echo "     BINARY INSTALLER v2.0 - OpenWrt"
    echo "============================================"
    
    set -- $BINARIES
    TOTAL=$#
    
    i=1
    INSTALLED_COUNT=0
    
    for f in $BINARIES; do
        if binary_exists "$f"; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            STATUS="${GREEN}[INSTALLED]${NC}"
        else
            STATUS="${RED}[MISSING]${NC}"
        fi
        printf "  %2d) %-15s %b\n" "$i" "$f" "$STATUS"
        i=$((i+1))
    done
    
    echo "--------------------------------------------"
    printf "  %2d) %-15s\n" "$i" "Install ALL"
    i=$((i+1))
    printf "  %2d) %-15s\n" "$i" "Check for updates"
    echo "  0) Exit"
    echo "============================================"
    printf "Installed: ${GREEN}$INSTALLED_COUNT${NC}/$TOTAL  |  Directory: $DATA_DIR\n"
    echo "============================================"
    printf "Your choice [0-$i]: "
    read choice

    case "$choice" in
        0) 
            print_green "Goodbye!"
            exit 0 
            ;;
        $((TOTAL+1))) 
            install_all_binaries 
            ;;
        $((TOTAL+2))) 
            print_blue "Checking for updates..."
            fetch_binaries
            print_green "Update check complete!"
            ;;
        *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$TOTAL" ]; then
                j=1
                for f in $BINARIES; do
                    if [ "$j" -eq "$choice" ]; then
                        install_binary "$f"
                        break
                    fi
                    j=$((j+1))
                done
            else
                print_red "Invalid choice!"
            fi
            ;;
    esac
}

# ---------- Show System Info ----------
show_system_info() {
    echo ""
    print_blue "System Information:"
    echo "  - OS: $(uname -o 2>/dev/null || echo 'Unknown')"
    echo "  - Kernel: $(uname -r)"
    echo "  - Architecture: $(uname -m)"
    echo "  - BusyBox: $(busybox --help 2>&1 | head -1 || echo 'Not found')"
    echo "  - Storage: $(df -h "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo 'Unknown') free"
    echo ""
}

# ---------- Main ----------
main() {
    check_root
    ensure_data_dir
    fetch_binaries
    show_system_info

    while true; do
        show_menu
        echo ""
        print_yellow "Press Enter to continue..."
        read dummy
    done
}

# Start
main
