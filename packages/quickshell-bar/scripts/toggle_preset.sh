#!/usr/bin/env bash

# Waybar input-remapper preset toggle
# Cycles through presets in alphabetical order

PRESETS_DIR="/home/vadyanik/.config/input-remapper-2/presets/SIGMACHIP USB Keyboard"
DEVICE="SIGMACHIP USB Keyboard"

# Get list of available presets (sorted alphabetically, without .json extension)
# Returns presets as newline-separated values (handles spaces correctly)
get_presets() {
    if [[ ! -d "$PRESETS_DIR" ]]; then
        echo "ERROR" >&2
        return 1
    fi
    find "$PRESETS_DIR" -maxdepth 1 -name "*.json" -type f -printf '%f\n' | sed 's/\.json$//' | sort
}

# Get the currently active preset from input-remapper's config
get_active_preset() {
    # Check input-remapper's config.json autoload section
    local config_file="$HOME/.config/input-remapper-2/config.json"
    if [[ -f "$config_file" ]]; then
        # Extract the preset name from autoload section
        local active=$(grep "$DEVICE" "$config_file" | sed 's/.*": "\([^"]*\)".*/\1/')
        if [[ -n "$active" ]]; then
            echo "$active"
            return 0
        fi
    fi

    # Fallback: return the first preset
    get_presets | head -1
}

# Toggle to next preset
toggle_preset() {
    # Read presets into array, handling spaces correctly
    local -a presets
    while IFS= read -r preset; do
        presets+=("$preset")
    done < <(get_presets)

    local current=$(get_active_preset)

    # Find the index of the current preset
    local current_index=-1
    for i in "${!presets[@]}"; do
        if [[ "${presets[$i]}" == "$current" ]]; then
            current_index=$i
            break
        fi
    done

    # If current preset not found, start from first
    if [[ $current_index -eq -1 ]]; then
        current_index=0
    fi

    # Calculate next index
    local next_index=$(( (current_index + 1) % ${#presets[@]} ))
    local next_preset="${presets[$next_index]}"

    # Update the config.json with the next preset
    local config_file="$HOME/.config/input-remapper-2/config.json"
    if [[ -f "$config_file" ]]; then
        # Create a backup just in case
        cp "$config_file" "$config_file.backup"

        # Use sed with proper escaping for special characters
        local device_escaped=$(printf '%s\n' "$DEVICE" | sed -e 's/[[\.*^$/]/\\&/g')
        local preset_escaped=$(printf '%s\n' "$next_preset" | sed -e 's/[\/&]/\\&/g')

        sed -i "s/\"$device_escaped\": \"[^\"]*\"/\"$device_escaped\": \"$preset_escaped\"/" "$config_file"
    fi

    # Trigger autoload to apply the new config (non-blocking)
    input-remapper-control --command autoload 2>/dev/null &

    echo "$next_preset"
}

# Output current preset for display
display_current() {
    get_active_preset
}

# Main logic
case "${1:-display}" in
    toggle)
        toggle_preset
        ;;
    display)
        display_current
        ;;
    *)
        display_current
        ;;
esac
