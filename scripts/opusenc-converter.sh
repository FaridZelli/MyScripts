#!/bin/bash

# https://github.com/FaridZelli/MyScripts

# Ensure opus-tools is installed
if ! command -v opusenc &> /dev/null; then
    echo -e "\e[31mError: 'opusenc' is not installed or not in your PATH.\e[0m"
    echo "Please install it (e.g., sudo apt install opus-tools) and try again."
    exit 1
fi

echo -e "\e[1;36m=== Batch Opus Encoder ===\e[0m\n"

# 1. Ask for source and output directories
read -e -r -p "Enter source directory: " SRC_DIR
if [[ ! -d "$SRC_DIR" ]]; then
    echo -e "\e[31mError: Source directory does not exist.\e[0m"
    exit 1
fi

read -e -r -p "Enter output directory: " OUT_DIR
mkdir -p "$OUT_DIR" || { echo "Failed to create output directory."; exit 1; }

# Normalize paths to absolute paths
SRC_DIR=$(realpath "$SRC_DIR")
OUT_DIR=$(realpath "$OUT_DIR")

# 2. Ask for bitrate
echo ""
while true; do
    read -r -p "Enter target bitrate in kbps [Enter = 384]: " BITRATE
    BITRATE="${BITRATE:-384}"

    if [[ "$BITRATE" =~ ^[1-9][0-9]*$ ]]; then
        break
    fi

    echo -e "\e[31mError: Bitrate must be a positive number.\e[0m"
done

# 3. Ask for the audio type
echo -e "\nSelect the audio type:"
echo "1) Music (--music)"
echo "2) Speech (--speech)"
echo ""
while true; do
    read -r -p "Choice (1/2) [Enter = 1]: " type_choice
    type_choice="${type_choice//$'\r'/}"
    type_choice="${type_choice:-1}"

    case "$type_choice" in
        1)
            TYPE_FLAG="--music"
            break
            ;;
        2)
            TYPE_FLAG="--speech"
            break
            ;;
        *)
            echo -e "\e[31mError: Invalid choice. Please enter 1 or 2.\e[0m"
            ;;
    esac
done

# 4. Ask what metadata to keep
echo -e "\nWhat metadata would you like to keep?"
echo "1) Keep all metadata"
echo "2) Remove cover art"
echo "3) Remove all metadata"
echo ""
while true; do
    read -r -p "Choice (1/2/3) [Enter = 1]: " meta_choice
    meta_choice="${meta_choice//$'\r'/}"
    meta_choice="${meta_choice:-1}"

    case "$meta_choice" in
        1)
            META_FLAGS=""
            break
            ;;
        2)
            META_FLAGS="--discard-pictures"
            break
            ;;
        3)
            META_FLAGS="--discard-comments --discard-pictures"
            break
            ;;
        *)
            echo -e "\e[31mError: Invalid choice. Please enter 1, 2, or 3.\e[0m"
            ;;
    esac
done

# 5. Ask whether to preserve modification dates
echo -e "\nPreserve original file modification dates on output files?"
echo "1) Yes"
echo "2) No"
echo ""
while true; do
    read -r -p "Choice (1/2) [Enter = 1]: " preserve_choice
    preserve_choice="${preserve_choice//$'\r'/}"
    preserve_choice="${preserve_choice:-1}"

    case "$preserve_choice" in
        1)
            PRESERVE_DATES=true
            PRESERVE_DATES_LABEL="Yes"
            break
            ;;
        2)
            PRESERVE_DATES=false
            PRESERVE_DATES_LABEL="No"
            break
            ;;
        *)
            echo -e "\e[31mError: Invalid choice. Please enter 1 or 2.\e[0m"
            ;;
    esac
done

# 6. Ask whether to sanitize output filenames
echo -e "\nReplace invalid filename characters (<>:\"/\\|?*) with underscores?"
echo "1) Yes"
echo "2) No"
echo ""
while true; do
    read -r -p "Choice (1/2) [Enter = 1]: " sanitize_choice
    sanitize_choice="${sanitize_choice//$'\r'/}"
    sanitize_choice="${sanitize_choice:-1}"

    case "$sanitize_choice" in
        1)
            SANITIZE_NAMES=true
            SANITIZE_NAMES_LABEL="Yes"
            break
            ;;
        2)
            SANITIZE_NAMES=false
            SANITIZE_NAMES_LABEL="No"
            break
            ;;
        *)
            echo -e "\e[31mError: Invalid choice. Please enter 1 or 2.\e[0m"
            ;;
    esac
done

# 7. Review Settings
echo -e "\n\e[1;33m=========================================\e[0m"
echo -e "\e[1;33m             SETTINGS REVIEW             \e[0m"
echo -e "\e[1;33m=========================================\e[0m"
echo -e "Source Directory : $SRC_DIR"
echo -e "Output Directory : $OUT_DIR"
echo -e "Audio Type       : $TYPE_FLAG"
echo -e "Bitrate          : ${BITRATE} kbps (VBR)"
echo -e "Metadata Policy  : ${META_FLAGS:-Keep All}"
echo -e "Preserve Dates   : $PRESERVE_DATES_LABEL"
echo -e "Sanitize Names   : $SANITIZE_NAMES_LABEL"
echo -e "\n\e[1;36mExact command to be executed per file:\e[0m"
echo -e "opusenc --quiet --vbr $TYPE_FLAG --bitrate $BITRATE $META_FLAGS \"<input_file>\" \"<output_file.opus>\""
echo -e "\e[1;33m=========================================\e[0m\n"

read -r -p "Press Enter to start encoding, or Ctrl+C to abort..."

# 8. Find files and process
echo -e "\n\e[1;34mScanning for supported files (WAV, FLAC, AIFF, OGG)...\e[0m"

# Count total valid files first
TOTAL_FILES=$(find "$SRC_DIR" -type f \( -iname "*.wav" -o -iname "*.flac" -o -iname "*.aiff" -o -iname "*.ogg" \) | wc -l)
if [[ $TOTAL_FILES -eq 0 ]]; then
    echo -e "\e[31mNo supported audio files found in $SRC_DIR.\e[0m"
    exit 0
fi

echo -e "Found \e[1;32m$TOTAL_FILES\e[0m files to process.\n"

CURRENT=0
SUCCESS=0
FAILED=0

# Use a while loop with process substitution to handle spaces in filenames safely
while IFS= read -r -d '' file; do
    ((CURRENT++))

    # Calculate output path maintaining the original directory structure
    rel_path="${file#$SRC_DIR/}"
    rel_dir=$(dirname "$rel_path")
    filename=$(basename "$file")
    basext="${filename%.*}"

    # Optionally sanitize output filename
    if [[ "$SANITIZE_NAMES" == true ]]; then
        basext=$(printf "%s" "$basext" | sed 's~[<>:"/\\|?*]~_~g')
    fi

    # Create target directory
    if [[ "$rel_dir" == "." ]]; then
        target_dir="$OUT_DIR"
    else
        target_dir="$OUT_DIR/$rel_dir"
        mkdir -p "$target_dir"
    fi

    target_file="$target_dir/$basext.opus"

    # Clean visual progress output
    echo -e "[\e[1;32m${CURRENT}\e[0m/\e[1;32m${TOTAL_FILES}\e[0m] Encoding: \e[36m${rel_path}\e[0m"

    # Start encoding
    opusenc --quiet --vbr $TYPE_FLAG --bitrate "$BITRATE" $META_FLAGS "$file" "$target_file"

    if [[ $? -eq 0 ]]; then
        ((SUCCESS++))

        # Optionally preserve original modification date
        if [[ "$PRESERVE_DATES" == true ]]; then
            touch -r "$file" "$target_file"
        fi
    else
        echo -e "\e[31m -> Error encoding ${filename}\e[0m"
        ((FAILED++))
    fi

done < <(find "$SRC_DIR" -type f \( -iname "*.wav" -o -iname "*.flac" -o -iname "*.aiff" -o -iname "*.ogg" \) -print0)

# 9. Final Summary
echo -e "\n\e[1;32mEncoding Complete!\e[0m"
echo -e "Successfully encoded : \e[1;32m$SUCCESS\e[0m"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed to encode     : \e[31m$FAILED\e[0m"
fi
