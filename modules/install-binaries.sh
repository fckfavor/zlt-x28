#!/bin/sh

# =============================
# BINARY INSTALLER v3.1 - ZIP EDITION
# OpenWrt / BusyBox Optimized
# Fixed -o output naming
# =============================

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
TEMP_DIR="/tmp/zlt-install"
GITHUB_ZIP="https://github.com/fckfavor/zlt-x28/archive/refs/heads/main.zip"
BINARY_PATH="zlt-x28-main/binaries"

# ---------- Print Functions ----------
print_green() { echo -e "${GREEN}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_blue() { echo -e "${BLUE}$1${NC}"; }

# ---------- Download with explicit output ----------
download_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"
    
    print_blue "Downloading repository as ZIP..."
    print_yellow "URL: $GITHUB_ZIP"
    print_yellow "Output: $ZIP_FILE"
    
    # Create temp dir
    mkdir -p "$TEMP_DIR"
    
    # Try wget first with explicit -O
    if command -v wget >/dev/null 2>&1; then
        print_blue "Using wget..."
        wget -O "$ZIP_FILE" "$GITHUB_ZIP" 2>&1 | while read line; do
            if echo "$line" | grep -q '%'; then
                PERCENT=$(echo "$line" | grep -o '[0-9]\+%' | head -1)
                if [ -n "$PERCENT" ]; then
                    printf "\r${BLUE}Downloading: %s${NC}" "$PERCENT"
                fi
            fi
        done
        printf "\n"
    else
        # Fallback to curl with explicit -o
        print_blue "Using curl..."
        curl -L -o "$ZIP_FILE" "$GITHUB_ZIP" --progress-bar
    fi
    
    # Check if download succeeded
    if [ ! -f "$ZIP_FILE" ]; then
        print_red "Download failed: $ZIP_FILE not created"
        return 1
    fi
    
    if [ ! -s "$ZIP_FILE" ]; then
        print_red "Download failed: $ZIP_FILE is empty"
        rm -f "$ZIP_FILE"
        return 1
    fi
    
    SIZE=$(ls -l "$ZIP_FILE" | awk '{print $5}')
    print_green "✓ ZIP downloaded: $SIZE bytes"
    print_green "  Location: $ZIP_FILE"
    return 0
}

# ---------- Extract ZIP ----------
extract_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"
    
    if [ ! -f "$ZIP_FILE" ]; then
        print_red "ZIP file not found: $ZIP_FILE"
        return 1
    fi
    
    print_blue "Extracting ZIP..."
    cd "$TEMP_DIR"
    
    # Try multiple extraction methods
    if command -v unzip >/dev/null 2>&1; then
        print_blue "Using unzip..."
        unzip -q "$ZIP_FILE"
    elif command -v tar >/dev/null 2>&1; then
        print_blue "Using tar..."
        tar -xf "$ZIP_FILE" 2>/dev/null
    else
        print_blue "Using busybox unzip..."
        busybox unzip "$ZIP_FILE" 2>/dev/null
    fi
    
    # Check if extraction worked
    if [ -d "$TEMP_DIR/zlt-x28-main" ]; then
        print_green "✓ Extraction complete!"
        print_green "  Extracted to: $TEMP_DIR/zlt-x28-main"
        return 0
    else
        print_red "Extraction failed!"
        ls -la "$TEMP_DIR"
        return 1
    fi
}

# ---------- List Available Binaries ----------
list_binaries() {
    BINARY_SOURCE="$TEMP_DIR/$BINARY_PATH"
    
    print_blue "Looking for binaries in: $BINARY_SOURCE"
    
    if [ ! -d "$BINARY_SOURCE" ]; then
        print_red "Binary directory not found!"
        print_yellow "Contents of $TEMP_DIR:"
        ls -la "$TEMP_DIR"
        print_yellow "Searching for binaries directory..."
        find "$TEMP_DIR" -name "binaries" -type d 2>/dev/null
        return 1
    fi
    
    # Get all files in binaries directory
    BINARIES=$(ls -1 "$BINARY_SOURCE" 2>/dev/null | grep -v '^$')
    
    if [ -z "$BINARIES" ]; then
        print_red "No binaries found in ZIP!"
        return 1
    fi
    
    COUNT=$(echo "$BINARIES" | wc -l)
    print_green "✓ Found $COUNT binaries in ZIP:"
    echo "----------------------------------------"
    for bin in $BINARIES; do
        if [ -f "$BINARY_SOURCE/$bin" ]; then
            SIZE=$(ls -l "$BINARY_SOURCE/$bin" | awk '{print $5}')
            HUMAN_SIZE=$([ $SIZE -gt 1048576 ] && echo "$((SIZE / 1048576))MB" || echo "$((SIZE / 1024))KB")
            printf "  %-15s %s bytes (%s)\n" "$bin" "$SIZE" "$HUMAN_SIZE"
        fi
    done
    echo "----------------------------------------"
    
    return 0
}

# ---------- Check if Binary Exists ----------
binary_exists() {
    BIN_NAME="$1"
    
    if [ -f "$DATA_DIR/$BIN_NAME" ] && [ -x "$DATA_DIR/$BIN_NAME" ]; then
        return 0
    fi
    return 1
}

# ---------- Install Binary from ZIP ----------
install_binary() {
    BINARY_NAME="$1"
    SOURCE="$TEMP_DIR/$BINARY_PATH/$BINARY_NAME"
    DEST="$DATA_DIR/$BINARY_NAME"
    
    if [ ! -f "$SOURCE" ]; then
        print_red "Source not found: $SOURCE"
        return 1
    fi
    
    # Check if already installed
    if binary_exists "$BINARY_NAME"; then
        LOCAL_SIZE=$(ls -l "$DEST" 2>/dev/null | awk '{print $5}')
        SOURCE_SIZE=$(ls -l "$SOURCE" | awk '{print $5}')
        
        print_yellow "✓ $BINARY_NAME already installed"
        print_yellow "  Current: $LOCAL_SIZE bytes"
        print_yellow "  New: $SOURCE_SIZE bytes"
        
        printf "Overwrite? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi
    
    print_blue "Installing: $BINARY_NAME"
    
    # Copy binary
    cp "$SOURCE" "$DEST"
    chmod +x "$DEST"
    
    # Create symlink
    if [ -L "/usr/bin/$BINARY_NAME" ]; then
        rm -f "/usr/bin/$BINARY_NAME"
    fi
    ln -sf "$DEST" "/usr/bin/$BINARY_NAME" 2>/dev/null
    
    SIZE=$(ls -l "$DEST" | awk '{print $5}')
    HUMAN_SIZE=$([ $SIZE -gt 1048576 ] && echo "$((SIZE / 1048576))MB" || echo "$((SIZE / 1024))KB")
    print_green "✓ $BINARY_NAME installed ($HUMAN_SIZE)"
}

# ---------- Install All Binaries ----------
install_all_binaries() {
    SOURCE_DIR="$TEMP_DIR/$BINARY_PATH"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        print_red "Source directory not found!"
        return 1
    fi
    
    for bin in $BINARIES; do
        echo ""
        install_binary "$bin"
    done
}

# ---------- Special Handling for BusyBox ----------
handle_busybox() {
    if binary_exists "busybox"; then
        print_yellow "✓ BusyBox already installed"
        printf "Reinstall? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi
    
    # Backup original busybox
    BUSYBOX_PATH=$(which busybox 2>/dev/null)
    if [ -n "$BUSYBOX_PATH" ] && [ -f "$BUSYBOX_PATH" ] && [ ! -L "$BUSYBOX_PATH" ]; then
        print_yellow "Backing up original: $BUSYBOX_PATH → ${BUSYBOX_PATH}.backup"
        mv "$BUSYBOX_PATH" "${BUSYBOX_PATH}.backup"
    fi
    
    install_binary "busybox"
    
    print_green "✓ BusyBox ready!"
    "$DATA_DIR/busybox" --help | head -2
}

# ---------- Cleanup ----------
cleanup() {
    print_yellow "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    print_green "✓ Cleanup complete!"
}

# ---------- Root Check ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_red "Error: Root privileges required!"
        exit 1
    fi
}

# ---------- Create Directories ----------
create_dirs() {
    print_yellow "Creating directories..."
    mkdir -p "$DATA_DIR"
    mkdir -p "$TEMP_DIR"
    print_green "✓ Data directory: $DATA_DIR"
    print_green "✓ Temp directory: $TEMP_DIR"
}

# ---------- Show Menu ----------
show_menu() {
    clear
    echo "============================================"
    echo "  BINARY INSTALLER v3.1 - ZIP EDITION"
    echo "         OpenWrt / BusyBox"
    echo "============================================"
    
    i=1
    INSTALLED_COUNT=0
    TOTAL_COUNT=0
    
    # Convert BINARIES to list
    for f in $BINARIES; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if binary_exists "$f"; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            STATUS="${GREEN}[✓]${NC}"
        else
            STATUS="${RED}[ ]${NC}"
        fi
        printf "  %2d) %-15s %b\n" "$i" "$f" "$STATUS"
        i=$((i+1))
    done
    
    echo "--------------------------------------------"
    printf "  %2d) %-15s\n" "$i" "Install ALL"
    i=$((i+1))
    printf "  %2d) %-15s\n" "$i" "Clean & Exit"
    echo "  0) Exit"
    echo "============================================"
    printf "Installed: ${GREEN}$INSTALLED_COUNT${NC}/$TOTAL_COUNT\n"
    printf "Source: ZIP (local)\n"
    echo "============================================"
    printf "Your choice [0-$i]: "
    read choice

    case "$choice" in
        0) 
            cleanup
            print_green "Goodbye!"
            exit 0 
            ;;
        $((TOTAL_COUNT+1))) 
            install_all_binaries 
            ;;
        $((TOTAL_COUNT+2))) 
            cleanup
            exit 0
            ;;
        *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$TOTAL_COUNT" ]; then
                j=1
                for f in $BINARIES; do
                    if [ "$j" -eq "$choice" ]; then
                        if [ "$f" = "busybox" ]; then
                            handle_busybox
                        else
                            install_binary "$f"
                        fi
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

# ---------- Main ----------
main() {
    check_root
    create_dirs
    
    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║     STEP 1/3: DOWNLOADING ZIP       ║"
    print_blue "╚══════════════════════════════════════╝"
    echo ""
    download_zip || exit 1
    
    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║     STEP 2/3: EXTRACTING ZIP        ║"
    print_blue "╚══════════════════════════════════════╝"
    echo ""
    extract_zip || exit 1
    
    echo ""
    print_blue "╔══════════════════════════════════════╗"
    print_blue "║     STEP 3/3: LISTING BINARIES      ║"
    print_blue "╚══════════════════════════════════════╝"
    echo ""
    list_binaries || exit 1
    
    echo ""
    print_green "╔══════════════════════════════════════╗"
    print_green "║     ✓ READY TO INSTALL               ║"
    print_green "╚══════════════════════════════════════╝"
    echo ""
    
    while true; do
        show_menu
        echo ""
        print_yellow "Press Enter to continue..."
        read dummy
    done
}

# Start
main
