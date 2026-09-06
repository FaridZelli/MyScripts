#!/bin/bash

# https://github.com/FaridZelli/MyScripts

# Check for required dependencies
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed or not in PATH."
    exit 1
fi
if ! command -v ffprobe &> /dev/null; then
    echo "Error: ffprobe is not installed or not in PATH. It is required to filter non-audio files."
    exit 1
fi

# Initialize flags and variables
SORT_PEAK=false
SORT_LOUDNESS=false
OUTPUT_FILE=""
OUTPUT_TO_FILE=false
HELP=false

show_help() {
    cat << 'EOF'
Audio Loudness Analysis Tool (ffmpeg)

This script analyzes audio files in the current directory to extract:

    Highest Peak:
        Measured in Decibels (dB). This is the maximum true peak level of the 
        audio signal. 0 dB is typically the maximum level before digital clipping 
        occurs (0 dBFS). Values are usually negative.
        
    Integrated Loudness:
        Measured in Loudness Units relative to Full Scale (LUFS). This is a 
        standardized measurement (ITU-R BS.1770 / EBU R128) of the average 
        perceived loudness over the entire duration of the audio. It accounts 
        for human hearing sensitivity (K-weighting) and is widely used for 
        broadcast and streaming normalization (e.g., -14 LUFS for Spotify).

USAGE:
    ./ffmpeg-loudness-check.sh [OPTIONS]

OPTIONS:
    -p, --list-peak
        Sort the output list from lowest to highest "Highest Peak" (volumedetect).
        Lower values (more negative, e.g., -60 dB) appear first.

    -l, --list-loudness
        Sort the output list from lowest to highest "Integrated Loudness" (ebur128).
        Lower values (more negative, e.g., -30 LUFS) appear first.

    -o, --output [filename]
        Save the output to a file instead of printing to the console.
        If [filename] is omitted, it saves to the current directory using the
        current date and time as the filename (e.g., 20240520_143000.txt).

    -h, --help
        Display this help message and exit.

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--list-peak)
            SORT_PEAK=true
            shift
            ;;
        -l|--list-loudness)
            SORT_LOUDNESS=true
            shift
            ;;
        -o|--output)
            OUTPUT_TO_FILE=true
            if [[ -n "$2" && "$2" != -* ]]; then
                OUTPUT_FILE="$2"
                shift 2
            else
                OUTPUT_FILE="$(date +%Y%m%d_%H%M%S).txt"
                shift
            fi
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ "$HELP" == true ]]; then
    show_help
    exit 0
fi

# Create a temporary file to store results
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE" "$TEMP_FILE.sorted"' EXIT

# Iterate over all files in the current directory
for file in *; do
    [[ -f "$file" ]] || continue
    
    # Check if file has an audio stream using ffprobe
    if ! ffprobe -v error -select_streams a -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | grep -q "audio"; then
        continue
    fi

    # Extract Highest Peak
    max_vol=$(ffmpeg -nostdin -hide_banner -i "$file" -af volumedetect -f null - 2>&1 | awk '/max_volume:/ {for(i=1;i<=NF;i++) if($i ~ /max_volume:/) {print $(i+1); exit}}')
    
    # Extract Integrated Loudness
    ebur_out=$(ffmpeg -nostdin -hide_banner -i "$file" -af ebur128 -f null - 2>&1)
    int_loudness=$(echo "$ebur_out" | awk '/Integrated loudness:/ { found=1 } found && /I:/ { for(i=1;i<=NF;i++) if($i ~ /I:/) { print $(i+1); exit } }')

    # Handle empty values (e.g. if ffmpeg fails on a corrupt file)
    if [[ -z "$max_vol" ]]; then
        max_val_sort="-1000.0"
        max_str="N/A"
    else
        max_val_sort="$max_vol"
        max_str="$max_vol dB"
    fi
    
    if [[ -z "$int_loudness" ]]; then
        int_val_sort="-1000.0"
        int_str="N/A"
    else
        int_val_sort="$int_loudness"
        int_str="$int_loudness LUFS"
    fi

    # Store in temp file: filename | display_peak | display_loudness | sort_peak | sort_loudness
    printf "%s|%s|%s|%s|%s\n" "$file" "$max_str" "$int_str" "$max_val_sort" "$int_val_sort" >> "$TEMP_FILE"
done

# Check if any files were processed
if [[ ! -s "$TEMP_FILE" ]]; then
    echo "No valid audio/video files found in the current directory."
    exit 0
fi

# Sort results based on flags (handles both used together)
SORT_ARGS=()
if [[ "$SORT_PEAK" == true ]]; then
    SORT_ARGS+=("-k4,4" "-g")
fi
if [[ "$SORT_LOUDNESS" == true ]]; then
    SORT_ARGS+=("-k5,5" "-g")
fi

if [[ ${#SORT_ARGS[@]} -gt 0 ]]; then
    sort -t '|' "${SORT_ARGS[@]}" "$TEMP_FILE" > "$TEMP_FILE.sorted"
    mv "$TEMP_FILE.sorted" "$TEMP_FILE"
fi

# Function to print formatted output
print_results() {
    printf "\n%-40s | %15s | %20s\n" "Filename" "Highest Peak" "Integrated Loudness"
    printf "%-40s-+-%-15s-+-%-20s\n" "----------------------------------------" "---------------" "--------------------"
    
    while IFS='|' read -r file peak_str loud_str _ _; do
        # Truncate filename if too long
        if [[ ${#file} -gt 40 ]]; then
            file_disp="${file:0:37}..."
        else
            file_disp="$file"
        fi
        
        printf "%-40s | %15s | %20s\n" "$file_disp" "$peak_str" "$loud_str"
    done < "$TEMP_FILE"
}

# Output results
if [[ "$OUTPUT_TO_FILE" == true ]]; then
    print_results > "$OUTPUT_FILE"
    echo "Output saved to $OUTPUT_FILE"
else
    print_results
fi
