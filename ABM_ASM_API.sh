#!/bin/zsh --no-rcs
set +x

# ABM-ASM API Tookit - Device Management Tool
# A script to manage devices in Apple School Manager and Apple Business Manager via the ASM/ABM API
  
SCRIPT_NAME="ABM-ASM API ToolKit"
SCRIPT_VERSION="1.4.0"
SCRIPT_LOG="/var/log/ABM-ASM_API_ToolKit.log"

# ============================================================================
# CONFIGURATION - UPDATE THESE VALUES (or leave empty to be prompted)
# ============================================================================
  
# Path to your client assertion JWT file (generated separately)
CLIENT_ASSERTION_FILE=""
  
# Or set the JWT directly
CLIENT_ASSERTION=""
  
# Your Client ID from ASM
CLIENT_ID=""
  
# Output directory - where to save the CSV and JSON files
OUTPUT_DIR=""
  
# API Configuration
# Apple Manager Type (school | business)
APPLE_MANAGER_TYPE=""
  
# ============================================================================
# FUNCTIONS
# ============================================================================

# Create log file if it doesn't exist
if [[ ! -f "${SCRIPT_LOG}" ]]; then
    touch "${SCRIPT_LOG}"
    chmod 644 "${SCRIPT_LOG}"
fi

# Logging functions
function update_script_log() {
    echo "${SCRIPT_NAME} (${SCRIPT_VERSION}): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}" | tee -a "${SCRIPT_LOG}"
}
# INFO - General information (shown to user and logged)
log_info() {
    update_script_log "[INFO]            ${1}"
}

# WARN - Warnings (shown to user and logged)
log_warn() {
    update_script_log "[WARN]            ${1}"
}

# ERROR - Errors (shown to user and logged)
log_error() {
    update_script_log "[ERROR]           ${1}"
}

# DEBUG - Debug info (only logged, not shown to user)
log_debug() {
    update_script_log "[DEBUG]           ${1}"
}

# SUCCESS - Success messages (shown to user and logged)
log_success() {
    update_script_log "[SUCCESS]         ${1}"
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install jq curl"
        exit 1
    fi
}

configure_apple_manager() {
    if [[ -z "$APPLE_MANAGER_TYPE" ]]; then
        echo ""
        echo "Apple Manager Type"
        echo "=================="
        echo "  1. Apple School Manager"
        echo "  2. Apple Business Manager"
        echo -n "Choose option (1 or 2): "
        read manager_option

        case "$manager_option" in
            1) APPLE_MANAGER_TYPE="school" ;;
            2) APPLE_MANAGER_TYPE="business" ;;
            *)
                echo "Error: Invalid selection"
                exit 1
                ;;
        esac
    fi

    case "$APPLE_MANAGER_TYPE" in
        school)
            AUTH_URL="https://account.apple.com/auth/oauth2/token"
            API_BASE_URL="https://api-school.apple.com/v1"
            SCOPE="school.api"
            ;;
        business)
            AUTH_URL="https://account.apple.com/auth/oauth2/token"
            API_BASE_URL="https://api-business.apple.com/v1"
            SCOPE="business.api"
            ;;
        *)
            echo "Error: Unknown Apple Manager type: $APPLE_MANAGER_TYPE"
            exit 1
            ;;
    esac

    echo ""
    echo "Using Apple $(
        [[ "$APPLE_MANAGER_TYPE" == "school" ]] && echo "School" || echo "Business"
    ) Manager"
    echo "  Auth URL:  $AUTH_URL"
    echo "  API Base:  $API_BASE_URL"
    echo "  Scope:     $SCOPE"
    echo ""
}
  
# Prompt for missing variables
prompt_for_variables() {
    echo "Configuration Setup"
    echo "==================="
    echo ""
    # Prompt for Client ID if not set
    if [[ -z "$CLIENT_ID" ]]; then
        echo -n "Enter your Client ID (e.g., SCHOOLAPI.123456): "
        read CLIENT_ID
        if [[ -z "$CLIENT_ID" ]]; then
            echo "Error: Client ID is required"
            exit 1
        fi
    else
        echo "Client ID: $CLIENT_ID"
    fi
    # Prompt for Client Assertion if not set
    if [[ -z "$CLIENT_ASSERTION" ]]; then
        if [[ -z "$CLIENT_ASSERTION_FILE" ]]; then
            echo ""
            echo "Client Assertion (JWT Token) Options:"
            echo "  1. Paste JWT token directly"
            echo "  2. Provide path to file containing JWT"
            echo -n "Choose option (1 or 2): "
            read jwt_option
            if [[ "$jwt_option" == "1" ]]; then
                echo -n "Paste your JWT token: "
                read CLIENT_ASSERTION
                if [[ -z "$CLIENT_ASSERTION" ]]; then
                    echo "Error: JWT token is required"
                    exit 1
                fi
            elif [[ "$jwt_option" == "2" ]]; then
                echo -n "Enter path to JWT file: "
                read CLIENT_ASSERTION_FILE
                # Expand ~ to home directory
                CLIENT_ASSERTION_FILE="${CLIENT_ASSERTION_FILE/#\~/$HOME}"
                if [[ ! -f "$CLIENT_ASSERTION_FILE" ]]; then
                    echo "Error: File not found: $CLIENT_ASSERTION_FILE"
                    exit 1
                fi
                CLIENT_ASSERTION=$(cat "$CLIENT_ASSERTION_FILE")
            else
                echo "Error: Invalid option"
                exit 1
            fi
        else
            # File path provided in config
            CLIENT_ASSERTION_FILE="${CLIENT_ASSERTION_FILE/#\~/$HOME}"
            if [[ ! -f "$CLIENT_ASSERTION_FILE" ]]; then
                echo "Error: JWT file not found: $CLIENT_ASSERTION_FILE"
                echo -n "Enter path to JWT file: "
                read CLIENT_ASSERTION_FILE
                CLIENT_ASSERTION_FILE="${CLIENT_ASSERTION_FILE/#\~/$HOME}"
                if [[ ! -f "$CLIENT_ASSERTION_FILE" ]]; then
                    echo "Error: File not found: $CLIENT_ASSERTION_FILE"
                    exit 1
                fi
            fi
            CLIENT_ASSERTION=$(cat "$CLIENT_ASSERTION_FILE")
            echo "Using JWT from file: $CLIENT_ASSERTION_FILE"
        fi
    else
        echo "Using JWT from configuration"
    fi

    # Prompt for Output Directory if not set
    if [[ -z "$OUTPUT_DIR" ]]; then
        echo ""
        echo -n "Do you need to set an output directory? (y/n, Enter for no): "
        read need_output
        
        if [[ "$need_output" =~ ^[Yy]$ ]]; then
            echo -n "Enter output directory (press Enter for current directory): "
            read OUTPUT_DIR
            if [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="."
            fi
            # Expand ~ to home directory
            OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
            echo "Output directory: $OUTPUT_DIR"
        else
            # Will be set later if needed
            OUTPUT_DIR=""
            echo "Output directory: Not set (will prompt if needed)"
        fi
    else
        # Expand ~ to home directory if already set
        OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
        echo "Output directory: $OUTPUT_DIR"
    fi

    echo ""
    echo "Configuration complete!"
    echo "======================="
    echo ""
}
  
# Create output directory if it doesn't exist
create_output_directory() {
    local dir="$1"
    # Expand ~ to home directory if needed
    dir="${dir/#\~/$HOME}"
    if [[ ! -d "$dir" ]]; then
        echo "Creating output directory: $dir"
        mkdir -p "$dir"
        chmod 655 "$dir"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to create directory: $dir" >&2
            exit 1
        fi
    fi
}
  
# Get access token using client assertion
get_access_token() {
    local client_assertion="$1"
    local client_id="$2"
    local scope="$3"
    echo "Requesting access token from Apple..." >&2
    echo "Using scope: $scope" >&2
    local response=$(curl -s -X POST \
        -H 'Host: account.apple.com' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        "https://account.apple.com/auth/oauth2/token?grant_type=client_credentials&client_id=${client_id}&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=${client_assertion}&scope=${scope}" \
        -w "\n%{http_code}")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
        echo "Error: Failed to get access token (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        exit 1
    fi
    # Check for error in response
    if echo "$body" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error from Apple:" >&2
        echo "$body" | jq '.' >&2
        exit 1
    fi
    local token=$(echo "$body" | jq -r '.access_token')
    local expires_in=$(echo "$body" | jq -r '.expires_in // "3600"')
    echo "Access token obtained (valid for ${expires_in} seconds / $(($expires_in / 60)) minutes)" >&2
    echo "$token"
}

# Fetch MDM servers
fetch_mdm_servers() {
    local access_token="$1"
    local url="${API_BASE_URL}/mdmServers"
    local response=$(curl -s -X GET "$url" \
        -H "Authorization: Bearer $access_token" \
        -w "\n%{http_code}")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
        echo "Error: Failed to fetch MDM servers (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        return 1
    fi
    echo "$body"
}

# Fetch devices assigned to an MDM server (with pagination)
fetch_mdm_server_devices() {
    local access_token="$1"
    local server_id="$2"
    local cursor="$3"
    local limit="${4:-1000}"
    
    local url="${API_BASE_URL}/mdmServers/${server_id}/relationships/devices?limit=$limit"
    [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
    
    local response=$(curl -s -X GET "$url" \
        -H "Authorization: Bearer $access_token" \
        -w "\n%{http_code}")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        echo "Error: Failed to fetch devices for MDM server (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        return 1
    fi
    
    echo "$body"
}

# Fetch assigned MDM server for a device
fetch_device_assigned_server() {
    local access_token="$1"
    local device_id="$2"
    
    local url="${API_BASE_URL}/orgDevices/${device_id}/relationships/assignedServer"
    
    local response=$(curl -s -X GET "$url" \
        -H "Authorization: Bearer $access_token" \
        -w "\n%{http_code}")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        # Return empty if not assigned or error
        echo '{"data": null}'
        return 1
    fi
    
    echo "$body"
}

# Fetch AppleCare coverage for a device
fetch_applecare_coverage() {
    local access_token="$1"
    local device_id="$2"
    
    local url="${API_BASE_URL}/orgDevices/${device_id}/appleCareCoverage"
    
    local response=$(curl -s -X GET "$url" \
        -H "Authorization: Bearer $access_token" \
        -w "\n%{http_code}")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        # Return empty array if no coverage found or error
        echo '{"data": []}'
        return 1
    fi
    
    echo "$body"
}

# Fetch single device by ID with full details
fetch_device_by_id() {
    local access_token="$1"
    local device_id="$2"
    
    local url="${API_BASE_URL}/orgDevices/${device_id}"
    local max_retries=5
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        local response
        response=$(curl -s -X GET "$url" \
            -H "Authorization: Bearer $access_token" \
            -w "\n%{http_code}")
        
        local http_code
        http_code=$(echo "$response" | tail -n1)
        local body
        body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" == "200" ]]; then
            # Validate JSON before returning
            if echo "$body" | jq -e '.data' >/dev/null 2>&1; then
                echo "$body"
                return 0
            else
                log_warn "Invalid JSON response for $device_id"
                return 1
            fi
        fi
        
        if [[ "$http_code" == "429" ]]; then
            local wait_time=$((attempt * 3))
            log_debug "Rate limited (429) for $device_id. Retry $attempt/$max_retries in ${wait_time}s"
            sleep "$wait_time"
            ((attempt++))
            continue
        fi
        
        # Other HTTP errors
        log_debug "HTTP $http_code for device $device_id"
        return 1
    done
    
    log_warn "Giving up on device $device_id after $max_retries retries"
    return 1
}

# Get full device details from device IDs
get_device_details_from_ids() {
    {
        # Explicitly disable any tracing in a subshell
        set +x
        setopt LOCAL_OPTIONS 2>/dev/null
        unsetopt XTRACE 2>/dev/null
        
        local access_token="$1"
        local device_ids_json="$2"
        local mdm_servers_json="$3"
        local fetch_applecare="$4"
        
        # Ensure input is valid JSON array
        if ! echo "$device_ids_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
            printf '[]'
            return
        fi
        
        local device_count
        device_count=$(echo "$device_ids_json" | jq 'length')
        
        if [[ "$device_count" -eq 0 ]]; then
            printf '[]'
            return
        fi
        
        # Build MDM server lookup table (ID -> Name)
        local mdm_lookup="{}"
        if [[ -n "$mdm_servers_json" ]]; then
            mdm_lookup=$(echo "$mdm_servers_json" | jq -r '.data | map({(.id): .attributes.serverName}) | add // {}' 2>/dev/null)
        fi
        
        # Use temporary file to accumulate results
        local temp_file
        temp_file=$(mktemp)
        
        local idx=0
        local success_count=0
        local error_count=0
        
        # Create array of device IDs
        local -a device_id_array
        while IFS= read -r device_id; do
            device_id_array+=("$device_id")
        done < <(echo "$device_ids_json" | jq -r '.[].id' 2>/dev/null)
        
        # Process each device ID
        for device_id in "${device_id_array[@]}"; do
            ((idx++))
            
            log_info "Processing device $idx of $device_count (ID: $device_id)" >> $SCRIPT_LOG
            # # Show progress (every 10 devices)
            # if [[ $((idx % 10)) -eq 1 ]] || [[ $idx -eq $device_count ]]; then
            #     echo "Processing device $idx of $device_count" >> $SCRIPT_LOG
            # fi
            
            # Fetch device
            local device
            device=$(fetch_device_by_id "$access_token" "$device_id" 2>/dev/null)
            
            [[ $? -ne 0 ]] || [[ -z "$device" ]] && { ((error_count++)); continue; }
            
            # Validate JSON
            echo "$device" | jq -e '.data' >/dev/null 2>&1 || { ((error_count++)); continue; }
            
            # Extract device data
            local device_data
            device_data=$(echo "$device" | jq -c '.data' 2>/dev/null)
            
            [[ -z "$device_data" ]] || [[ "$device_data" == "null" ]] && { ((error_count++)); continue; }
            
            # Fetch assigned MDM server
            local assigned_server
            assigned_server=$(fetch_device_assigned_server "$access_token" "$device_id" 2>/dev/null)
            
            local server_id
            server_id=$(echo "$assigned_server" | jq -r '.data.id // null' 2>/dev/null)
            
            if [[ "$server_id" != "null" ]] && [[ -n "$server_id" ]]; then
                local server_name
                server_name=$(echo "$mdm_lookup" | jq -r --arg id "$server_id" '.[$id] // $id' 2>/dev/null)
                device_data=$(echo "$device_data" | jq --arg id "$server_id" --arg name "$server_name" '. + {assignedMdmServerId: $id, assignedMdmServerName: $name}' 2>/dev/null)
            else
                device_data=$(echo "$device_data" | jq '. + {assignedMdmServerId: null, assignedMdmServerName: "Unassigned"}' 2>/dev/null)
            fi

            # Fetch AppleCare coverage if requested
            if [[ "$fetch_applecare" == "true" ]]; then
                local coverage
                coverage=$(fetch_applecare_coverage "$access_token" "$device_id" 2>/dev/null)
                local coverage_data
                coverage_data=$(echo "$coverage" | jq -c '.data // []' 2>/dev/null)
                
                # Add AppleCare coverage to device object
                device_data=$(echo "$device_data" | jq --argjson coverage "$coverage_data" '. + {appleCareCoverage: $coverage}' 2>/dev/null)
            fi
            
            # Validate and write
            if echo "$device_data" | jq -e 'type == "object"' >/dev/null 2>&1; then
                printf '%s\n' "$device_data" >> "$temp_file"
                ((success_count++))
            else
                ((error_count++))
            fi
            
            sleep 1.0
        done
        
        # Build JSON array from temp file
        local all_devices
        
        if [[ -f "$temp_file" ]] && [[ -s "$temp_file" ]]; then
            all_devices=$(jq -s '.' "$temp_file" 2>/dev/null)
            
            if [[ $? -ne 0 ]] || [[ -z "$all_devices" ]] || [[ "$all_devices" == "null" ]]; then
                all_devices="[]"
            fi
        else
            all_devices="[]"
        fi
        
        # Clean up
        rm -f "$temp_file"
        
        # Output only JSON
        printf '%s' "$all_devices"
        
    } 2>&1 | grep -v '^[a-zA-Z_][a-zA-Z0-9_]*=' | grep -v '^\${'
}

# Get devices for specific MDM servers
get_devices_for_mdm_servers() {
    local access_token="$1"
    shift
    local mdm_server_ids=("$@")
    
    local all_device_ids="[]"
    
    echo "Fetching devices from ${#mdm_server_ids[@]} MDM server(s)..." >&2
    echo "" >&2
    
    for server_id in "${mdm_server_ids[@]}"; do
        echo "  Processing MDM Server: $server_id" >&2
        
        local cursor=""
        local page=1
        
        while true; do
            echo "    Fetching page $page..." >&2
            
            local response=$(fetch_mdm_server_devices "$access_token" "$server_id" "$cursor")
            if [[ $? -ne 0 ]]; then
                break
            fi
            
            # Extract device IDs from this page
            local device_ids=$(echo "$response" | jq -c '.data // []')
            local device_count=$(echo "$device_ids" | jq 'length')
            
            # Merge with all device IDs (removing duplicates if device is in multiple servers)
            all_device_ids=$(echo "$all_device_ids" "$device_ids" | jq -s '.[0] + .[1] | unique_by(.id)')
            
            local total=$(echo "$all_device_ids" | jq 'length')
            echo "      Retrieved $device_count device IDs (Total unique: $total)" >&2
            
            # Get next cursor
            cursor=$(echo "$response" | jq -r '.meta.paging.nextCursor // empty')
            
            # Break if no more pages
            [[ -z "$cursor" ]] && break
            
            ((page++))
            sleep 0.2
        done
        
        echo "" >&2
    done
    
    echo "$all_device_ids"
}

# Select MDM servers for filtering
select_mdm_servers() {
    local mdm_servers="$1"
    
    echo ""
    echo "MDM Server Filter Options:"
    echo "  1. Export from specific MDM server(s)"
    echo "  2. Export all devices (no filter)"
    echo ""
    echo -n "Choose option (1-2): "
    read filter_choice
    
    local selected_servers=()
    
    if [[ "$filter_choice" == "1" ]]; then
        echo ""
        echo "Available MDM Servers:"
        echo "$mdm_servers" | jq -r '.data[] | "  \(.id) - \(.attributes.serverName)"'
        echo ""
        echo "Enter MDM Server IDs:"
        echo "  Options:"
        echo "    1. Comma-separated list (e.g., ID1,ID2,ID3)"
        echo "    2. One per line (empty line to finish)"
        echo ""
        echo -n "Choose input method (1 or 2): "
        read input_method
        
        if [[ "$input_method" == "1" ]]; then
            echo -n "Enter comma-separated MDM Server IDs: "
            read server_input
            
            # Split by comma and trim whitespace
            IFS=',' read -rA temp_array <<< "$server_input"
            for server_id in "${temp_array[@]}"; do
                server_id=$(echo "$server_id" | xargs)
                if [[ -n "$server_id" ]]; then
                    # Validate server ID
                    local server_exists=$(echo "$mdm_servers" | jq -r --arg id "$server_id" '.data[] | select(.id == $id) | .id')
                    if [[ -n "$server_exists" ]]; then
                        selected_servers+=("$server_id")
                    else
                        echo "Warning: MDM Server ID '$server_id' not found, skipping..."
                    fi
                fi
            done
        else
            echo "Enter MDM Server IDs (one per line, empty line to finish):"
            while true; do
                echo -n "MDM Server ID: "
                read server_id
                if [[ -z "$server_id" ]]; then
                    break
                fi
                # Validate server ID
                local server_exists=$(echo "$mdm_servers" | jq -r --arg id "$server_id" '.data[] | select(.id == $id) | .id')
                if [[ -n "$server_exists" ]]; then
                    selected_servers+=("$server_id")
                else
                    echo "Warning: MDM Server ID '$server_id' not found"
                fi
            done
        fi
        
        if [[ ${#selected_servers[@]} -eq 0 ]]; then
            echo "No valid MDM servers selected. Canceling export."
            echo "FILTER_CANCEL"
            return
        fi
        
        echo ""
        echo "Selected MDM Servers (${#selected_servers[@]}):"
        for server_id in "${selected_servers[@]}"; do
            local server_name=$(echo "$mdm_servers" | jq -r --arg id "$server_id" '.data[] | select(.id == $id) | .attributes.serverName')
            echo "  - $server_id ($server_name)"
        done
        
        # Return the array as a string
        echo "FILTER_SERVERS:${selected_servers[*]}"
        
    else
        # No filter - all devices
        echo "FILTER_ALL"
    fi
}

export_csv_devices() {
    local DEVICES="$1"
    local csv_file="$2"
    local fetch_applecare="$3"

    log_info "Creating CSV export: $csv_file"

    if [[ "$fetch_applecare" == "true" ]]; then
        echo "ID,Serial Number,Model,Product Family,Product Type,Status,Color,Capacity,Added to Org,Assigned MDM Server,WiFi MAC,Org Release Date,AppleCare Descriptions,AppleCare Statuses,AppleCare Start Dates,AppleCare End Dates,AppleCare Payment Types" > "$csv_file"

        echo "$DEVICES" | jq -r '.[] |
            .appleCareCoverage // [] as $coverage |
            [
                .id // "",
                .attributes.serialNumber // "",
                .attributes.deviceModel // "",
                .attributes.productFamily // "",
                .attributes.productType // "",
                .attributes.status // "",
                .attributes.color // "",
                .attributes.deviceCapacity // "",
                .attributes.addedToOrgDateTime // "",
                .assignedMdmServerName // "Unassigned",
                .attributes.wifiMacAddress // "",
                .attributes.releasedFromOrgDateTime // "",
                ($coverage | map(.attributes.description) | join(" | ")),
                ($coverage | map(.attributes.status) | join(" | ")),
                ($coverage | map(.attributes.startDateTime) | join(" | ")),
                ($coverage | map(.attributes.endDateTime // "No end date") | join(" | ")),
                ($coverage | map(.attributes.paymentType) | join(" | "))
            ] | @csv' >> "$csv_file"
    else
        echo "ID,Serial Number,Model,Product Family,Product Type,Status,Color,Capacity,Added to Org,Assigned MDM Server,WiFi MAC,Org Release Date" > "$csv_file"

        echo "$DEVICES" | jq -r '.[] | [
            .id // "",
            .attributes.serialNumber // "",
            .attributes.deviceModel // "",
            .attributes.productFamily // "",
            .attributes.productType // "",
            .attributes.status // "",
            .attributes.color // "",
            .attributes.deviceCapacity // "",
            .attributes.addedToOrgDateTime // "",
            .assignedMdmServerName // "Unassigned",
            .attributes.wifiMacAddress // "",
            .attributes.releasedFromOrgDateTime // ""
        ] | @csv' >> "$csv_file"
    fi

    echo "CSV saved to: $csv_file"
}

show_device_details() {
    local DEVICES="$1"

    # ---- Summary ----
    echo ""
    echo "========================================="
    echo "Export Summary"
    echo "========================================="
    echo "Total devices exported: $final_device_count"
    
    # Only show groupings if we have devices
    if [[ "$final_device_count" -gt 0 ]]; then
        echo ""
        echo "Devices by Model:"
        if echo "$DEVICES" | jq -e '.[0].attributes.deviceModel' >/dev/null 2>&1; then
            echo "$DEVICES" | jq -r 'group_by(.attributes.deviceModel) | .[] | "\(.[0].attributes.deviceModel): \(length)"' | sort -t: -k2 -rn | column -t -s:
        else
            echo "  (Model information not available)"
        fi
        
        echo ""
        echo "Devices by Status:"
        if echo "$DEVICES" | jq -e '.[0].attributes.status' >/dev/null 2>&1; then
            echo "$DEVICES" | jq -r 'group_by(.attributes.status) | .[] | "\(.[0].attributes.status): \(length)"' | sort -t: -k2 -rn | column -t -s:
        else
            echo "  (Status information not available)"
        fi
        
        echo ""
        echo "Devices by Product Family:"
        if echo "$DEVICES" | jq -e '.[0].attributes.productFamily' >/dev/null 2>&1; then
            echo "$DEVICES" | jq -r 'group_by(.attributes.productFamily) | .[] | "\(.[0].attributes.productFamily): \(length)"' | sort -t: -k2 -rn | column -t -s:
        else
            echo "  (Product family information not available)"
        fi
    fi

    echo ""
    echo "========================================="
    echo "Device Details"
    echo "========================================="

 echo "$DEVICES" | jq -c '.[]' | while read -r device; do
            echo ""
            echo "Serial: $(echo "$device" | jq -r '.attributes.serialNumber')"
            echo "  Model:            $(echo "$device" | jq -r '.attributes.deviceModel')"
            echo "  Family:           $(echo "$device" | jq -r '.attributes.productFamily')"
            echo "  Status:           $(echo "$device" | jq -r '.attributes.status')"
            echo "  Color:            $(echo "$device" | jq -r '.attributes.color // "N/A"')"
            echo "  Capacity:         $(echo "$device" | jq -r '.attributes.deviceCapacity // "N/A"')"
            echo "  Added to Org:     $(echo "$device" | jq -r '.attributes.addedToOrgDateTime')"
            echo "  Assigned MDM:     $(echo "$device" | jq -r '.assignedMdmServerName // "Unassigned"')"
            echo "  Wifi MAC:         $(echo "$device" | jq -r '.attributes.wifiMacAddress // "N/A"')"
            echo "  Org Release Date:  $(echo "$device" | jq -r '.attributes.releasedFromOrgDateTime // "N/A"')"
            # Show AppleCare coverage if available
            if echo "$device" | jq -e '.appleCareCoverage' >/dev/null 2>&1; then
                local coverage_count=$(echo "$device" | jq '.appleCareCoverage | length')
                if [[ "$coverage_count" -gt 0 ]]; then
                    echo "  AppleCare:"
                    echo "$device" | jq -c '.appleCareCoverage[]' | while read -r coverage; do
                        echo "    - $(echo "$coverage" | jq -r '.attributes.description')"
                        echo "      Status:   $(echo "$coverage" | jq -r '.attributes.status')"
                        echo "      Start:    $(echo "$coverage" | jq -r '.attributes.startDateTime')"
                        echo "      End:      $(echo "$coverage" | jq -r '.attributes.endDateTime // "No end date"')"
                        echo "      Payment:  $(echo "$coverage" | jq -r '.attributes.paymentType')"
                    done
                else
                    echo "  AppleCare:        No coverage"
                fi
            fi
        done
}

# Export devices with MDM filtering
export_devices_with_filter() {
    local access_token="$1"
    local mdm_servers="$2"
    local output_dir="$3"
    
    log_info "Starting device export process"
    
    echo ""
    echo "MDM Server Selection"
    echo "===================="
    
    # ---- Get selection (ONLY call once) ----
    local filter_result
    filter_result=$(select_mdm_servers_interactive "$mdm_servers")
    
    # ---- Handle cancel / errors ----
    if [[ "$filter_result" == "CANCEL" ]]; then
        log_info "Export canceled by user"
        echo "Export canceled by user."
        return
    fi
    
    if [[ "$filter_result" == ERROR:* ]]; then
        log_error "Selection error: ${filter_result#ERROR:}"
        echo "Selection error: ${filter_result#ERROR:}"
        return
    fi
    
    # ---- Parse selected server IDs ----
    local selected_server_ids=()
    if [[ "$filter_result" =~ ^SELECTED: ]]; then
        local server_ids="${filter_result#SELECTED:}"
        IFS=' ' read -rA selected_server_ids <<< "$server_ids"
    else
        log_error "Unexpected selection result: $filter_result"
        echo "Unexpected selection result: [$filter_result]"
        return
    fi
    
    if [[ "${#selected_server_ids[@]}" -eq 0 ]]; then
        log_warn "No valid MDM servers selected"
        echo "No valid MDM servers selected. Nothing to export."
        return
    fi
    
    echo ""
    echo "Selected MDM server(s):"
    for id in "${selected_server_ids[@]}"; do
        local name
        name=$(echo "$mdm_servers" | jq -r --arg id "$id" '.data[] | select(.id == $id) | .attributes.serverName')
        echo "  - $id ($name)"
        log_debug "Selected MDM server: $id ($name)"
    done
    
    # ---- Fetch device IDs from selected MDM servers ----
    echo ""
    log_info "Fetching device IDs from ${#selected_server_ids[@]} MDM server(s)"
    
    local device_ids
    device_ids=$(get_devices_for_mdm_servers "$access_token" "${selected_server_ids[@]}")
    
    local device_count
    device_count=$(echo "$device_ids" | jq 'length')
    
    if [[ "$device_count" -eq 0 ]]; then
        log_warn "No devices found in selected MDM server(s)"
        echo "No devices found in the selected MDM server(s)."
        return
    fi
    
    log_info "Found $device_count unique device(s)"
    echo ""
    echo "Found $device_count unique device(s). Fetching details..."
    log_info "Fetching full device details for $device_count devices"
    
    # Ask if user wants AppleCare coverage
    echo ""
    echo -n "Fetch AppleCare coverage for each device? (y/n): "
    read fetch_applecare_input
    local fetch_applecare="false"
    if [[ "$fetch_applecare_input" =~ ^[Yy]$ ]]; then
        fetch_applecare="true"
        log_info "AppleCare coverage will be fetched for each device"
        log_info "Note: This will take longer as it makes an additional API call per device."
    fi

    # ---- Fetch full device records ----
    local DEVICES
    DEVICES=$(get_device_details_from_ids "$access_token" "$device_ids" "$mdm_servers" "$fetch_applecare")

    log_debug "Returned data length: ${#DEVICES} characters"

    # Strip any progress messages that may have leaked into output
    # Remove lines that start with whitespace followed by [
    DEVICES=$(echo "$DEVICES" | sed '/^[[:space:]]*\[.*Processing\.\.\./d')

    # Debug: Save cleaned output to file for inspection
    local debug_file="${output_dir}/debug_output_$(date +%Y%m%d_%H%M%S).txt"
    printf '%s' "$DEVICES" > "$debug_file"
    log_debug "Cleaned output saved to: $debug_file"

    # Validate that DEVICES is valid JSON array
    if ! echo "$DEVICES" | jq -e 'type == "array"' >/dev/null 2>&1; then
        log_error "Device fetch returned invalid JSON data"
        echo ""
        echo "========================================="
        echo "Error: Device fetch returned invalid data"
        echo "========================================="
        echo ""
        echo "First 200 characters of output:"
        echo "${DEVICES:0:200}"
        echo ""
        echo "This could be due to:"
        echo "  - Shell debug output contaminating JSON"
        echo "  - Rate limiting from Apple's API"
        echo "  - Network connectivity issues"
        echo ""
        echo "Debug file saved to: $debug_file"
        echo "Check the log file for details: ${SCRIPT_LOG}"
        return
    fi
    
    local final_device_count
    final_device_count=$(echo "$DEVICES" | jq 'length')
    
    if [[ "$final_device_count" -eq 0 ]]; then
        log_warn "No devices were successfully retrieved"
        echo ""
        echo "========================================="
        echo "No devices were successfully retrieved"
        echo "========================================="
        return
    fi
    
    log_success "Retrieved $final_device_count of $device_count devices"
    
    echo ""
    echo "========================================="
    echo "Successfully retrieved $final_device_count of $device_count devices"
    echo "========================================="
    
    # ---- Output selection ----
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local json_file="${output_dir}/devices_${timestamp}.json"
    local csv_file="${output_dir}/devices_${timestamp}.csv"

    echo ""
    echo "Output Options"
    echo "=============="
    echo "1. Save JSON only"
    echo "2. Save CSV only"
    echo "3. Save BOTH JSON and CSV"
    echo "4. Show device details only (no files)"
    echo "5. Save JSON, CSV, and show details"
    echo "6. Return to main menu"
    echo ""
    echo -n "Choose an option (1-6): "
    read output_choice

    case "$output_choice" in
        1)
            log_info "Saving JSON to: $json_file"
            echo "$DEVICES" | jq '.' > "$json_file"
            echo "JSON saved to: $json_file"
            show_main_menu
            ;;
        2)
            export_csv_devices "$DEVICES" "$csv_file" "$fetch_applecare"
            show_main_menu
            ;;
        3)
            log_info "Saving JSON to: $json_file"
            echo "$DEVICES" | jq '.' > "$json_file"
            export_csv_devices "$DEVICES" "$csv_file" "$fetch_applecare"
            show_main_menu
            ;;
        4)
            show_device_details "$DEVICES"
            show_main_menu
            ;;
        5)
            log_info "Saving JSON to: $json_file"
            echo "$DEVICES" | jq '.' > "$json_file"
            export_csv_devices "$DEVICES" "$csv_file" "$fetch_applecare"
            show_device_details "$DEVICES"
            show_main_menu
            ;;
        6)
            echo "Returning to main menu."
            log_info "Returning to main menu."
            show_main_menu
            ;;
        *)
            echo "Invalid selection. Returning to main menu."
            log_warn "Invalid selection. Returning to main menu."
            show_main_menu
            return
            ;;
    esac

    # # ---- JSON export ----
    # log_info "Saving devices to: $json_file"
    # echo ""
    # echo "$DEVICES" | jq '.' > "$json_file"
    # echo "Devices saved to: $json_file"
    
    # # ---- CSV export ----
    # log_info "Creating CSV export: $csv_file"
    
    # if [[ "$fetch_applecare" == "true" ]]; then
    #     # CSV with AppleCare info - ONE ROW PER DEVICE
    #     echo "ID,Serial Number,Model,Product Family,Product Type,Status,Color,Capacity,Added to Org,Assigned MDM Server,WiFi MAC,Org Release Date,AppleCare Descriptions,AppleCare Statuses,AppleCare Start Dates,AppleCare End Dates,AppleCare Payment Types" > "$csv_file"
        
    # echo "$DEVICES" | jq -r '.[] |
    #     .appleCareCoverage // [] as $coverage |
    #     [
    #         .id // "",
    #         .attributes.serialNumber // "",
    #         .attributes.deviceModel // "",
    #         .attributes.productFamily // "",
    #         .attributes.productType // "",
    #         .attributes.status // "",
    #         .attributes.color // "",
    #         .attributes.deviceCapacity // "",
    #         .attributes.addedToOrgDateTime // "",
    #         .assignedMdmServerName // "Unassigned",
    #         .attributes.wifiMacAddress // "",
    #         .attributes.releasedFromOrgDateTime // "",

    #         ($coverage | map(.attributes.description) | join(" | ")) // "",
    #         ($coverage | map(.attributes.status) | join(" | ")) // "",
    #         ($coverage | map(.attributes.startDateTime) | join(" | ")) // "",
    #         ($coverage | map(.attributes.endDateTime // "No end date") | join(" | ")) // "",
    #         ($coverage | map(.attributes.paymentType) | join(" | ")) // ""
    #     ] | @csv' >> "$csv_file"
    # else
    #     # CSV without AppleCare info (original)
    #     echo "ID,Serial Number,Model,Product Family,Product Type,Status,Color,Capacity,Added to Org,Assigned MDM Server,WiFi MAC,Org Release Date" > "$csv_file"
        
    #     echo "$DEVICES" | jq -r '.[] | [
    #         .id // "",
    #         .attributes.serialNumber // "",
    #         .attributes.deviceModel // "",
    #         .attributes.productFamily // "",
    #         .attributes.productType // "",
    #         .attributes.status // "",
    #         .attributes.color // "",
    #         .attributes.deviceCapacity // "",
    #         .attributes.addedToOrgDateTime // "",
    #         .assignedMdmServerName // "Unassigned"
    #         .attributes.wifiMacAddress // "",
    #         .attributes.releasedFromOrgDateTime // ""
    #     ] | @csv' >> "$csv_file"
    # fi
    
    # echo "CSV export saved to: $csv_file"
    
    # log_success "Export completed: $final_device_count devices saved"
    
    # # ---- Summary ----
    # echo ""
    # echo "========================================="
    # echo "Export Summary"
    # echo "========================================="
    # echo "Total devices exported: $final_device_count"
    
    # # Only show groupings if we have devices
    # if [[ "$final_device_count" -gt 0 ]]; then
    #     echo ""
    #     echo "Devices by Model:"
    #     if echo "$DEVICES" | jq -e '.[0].attributes.deviceModel' >/dev/null 2>&1; then
    #         echo "$DEVICES" | jq -r 'group_by(.attributes.deviceModel) | .[] | "\(.[0].attributes.deviceModel): \(length)"' | sort -t: -k2 -rn | column -t -s:
    #     else
    #         echo "  (Model information not available)"
    #     fi
        
    #     echo ""
    #     echo "Devices by Status:"
    #     if echo "$DEVICES" | jq -e '.[0].attributes.status' >/dev/null 2>&1; then
    #         echo "$DEVICES" | jq -r 'group_by(.attributes.status) | .[] | "\(.[0].attributes.status): \(length)"' | sort -t: -k2 -rn | column -t -s:
    #     else
    #         echo "  (Status information not available)"
    #     fi
        
    #     echo ""
    #     echo "Devices by Product Family:"
    #     if echo "$DEVICES" | jq -e '.[0].attributes.productFamily' >/dev/null 2>&1; then
    #         echo "$DEVICES" | jq -r 'group_by(.attributes.productFamily) | .[] | "\(.[0].attributes.productFamily): \(length)"' | sort -t: -k2 -rn | column -t -s:
    #     else
    #         echo "  (Product family information not available)"
    #     fi
    # fi
    
    # echo ""
    # echo -n "View detailed device list? (y/n): "
    # read view_details
    
    # if [[ "$view_details" =~ ^[Yy]$ ]]; then
    #     echo ""
    #     echo "========================================="
    #     echo "Device Details"
    #     echo "========================================="
        
    #     echo "$DEVICES" | jq -c '.[]' | while read -r device; do
    #         echo ""
    #         echo "Serial: $(echo "$device" | jq -r '.attributes.serialNumber')"
    #         echo "  Model:            $(echo "$device" | jq -r '.attributes.deviceModel')"
    #         echo "  Family:           $(echo "$device" | jq -r '.attributes.productFamily')"
    #         echo "  Status:           $(echo "$device" | jq -r '.attributes.status')"
    #         echo "  Color:            $(echo "$device" | jq -r '.attributes.color // "N/A"')"
    #         echo "  Capacity:         $(echo "$device" | jq -r '.attributes.deviceCapacity // "N/A"')"
    #         echo "  Added to Org:     $(echo "$device" | jq -r '.attributes.addedToOrgDateTime')"
    #         echo "  Assigned MDM:     $(echo "$device" | jq -r '.assignedMdmServerName // "Unassigned"')"
    #         echo "  Wifi MAC:         $(echo "$device" | jq -r '.attributes.wifiMacAddress // "N/A"')"
    #         echo "  Org Release Date:  $(echo "$device" | jq -r '.attributes.releasedFromOrgDateTime // "N/A"')"
    #         # Show AppleCare coverage if available
    #         if echo "$device" | jq -e '.appleCareCoverage' >/dev/null 2>&1; then
    #             local coverage_count=$(echo "$device" | jq '.appleCareCoverage | length')
    #             if [[ "$coverage_count" -gt 0 ]]; then
    #                 echo "  AppleCare:"
    #                 echo "$device" | jq -c '.appleCareCoverage[]' | while read -r coverage; do
    #                     echo "    - $(echo "$coverage" | jq -r '.attributes.description')"
    #                     echo "      Status:   $(echo "$coverage" | jq -r '.attributes.status')"
    #                     echo "      Start:    $(echo "$coverage" | jq -r '.attributes.startDateTime')"
    #                     echo "      End:      $(echo "$coverage" | jq -r '.attributes.endDateTime // "No end date"')"
    #                     echo "      Payment:  $(echo "$coverage" | jq -r '.attributes.paymentType')"
    #                 done
    #             else
    #                 echo "  AppleCare:        No coverage"
    #             fi
    #         fi
    #     done
    # fi
}

  
# Assign devices to MDM server
assign_devices_to_mdm() {
    local access_token="$1"
    local mdm_server_id="$2"
    shift 2
    local device_ids=("$@")
    # Build devices array for JSON
    local devices_json="[]"
    for device_id in "${device_ids[@]}"; do
        devices_json=$(echo "$devices_json" | jq --arg id "$device_id" '. += [{"type": "orgDevices", "id": $id}]')
    done
    # Build request body
    local request_body=$(jq -n \
        --arg mdm_id "$mdm_server_id" \
        --argjson devices "$devices_json" \
        '{
            "data": {
                "type": "orgDeviceActivities",
                "attributes": {
                    "activityType": "ASSIGN_DEVICES"
                },
                "relationships": {
                    "mdmServer": {
                        "data": {
                            "type": "mdmServers",
                            "id": $mdm_id
                        }
                    },
                    "devices": {
                        "data": $devices
                    }
                }
            }
        }')
    local response=$(curl -s -X POST "${API_BASE_URL}/orgDeviceActivities" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        -w "\n%{http_code}")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    if [[ "$http_code" != "200" ]] && [[ "$http_code" != "201" ]]; then
        echo "Error: Failed to assign devices (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        return 1
    fi
    echo "$body"
}
  
# Unassign devices from MDM server
unassign_devices_from_mdm() {
    local access_token="$1"
    shift 1
    local device_ids=("$@")
    # Build devices array for JSON
    local devices_json="[]"
    for device_id in "${device_ids[@]}"; do
        devices_json=$(echo "$devices_json" | jq --arg id "$device_id" '. += [{"type": "orgDevices", "id": $id}]')
    done
    # Build request body
    local request_body=$(jq -n \
        --argjson devices "$devices_json" \
        '{
            "data": {
                "type": "orgDeviceActivities",
                "attributes": {
                    "activityType": "UNASSIGN_DEVICES"
                },
                "relationships": {
                    "devices": {
                        "data": $devices
                    }
                }
            }
        }')
    local response=$(curl -s -X POST "${API_BASE_URL}/orgDeviceActivities" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        -w "\n%{http_code}")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    if [[ "$http_code" != "200" ]] && [[ "$http_code" != "201" ]]; then
        echo "Error: Failed to unassign devices (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        return 1
    fi
    echo "$body"
}
  
# Get activity status
get_activity_status() {
    local access_token="$1"
    local activity_id="$2"
    local response=$(curl -s -X GET "${API_BASE_URL}/orgDeviceActivities/${activity_id}" \
        -H "Authorization: Bearer $access_token" \
        -w "\n%{http_code}")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
        echo "Error: Failed to get activity status (HTTP $http_code)" >&2
        echo "Response: $body" >&2
        return 1
    fi
    echo "$body"
}
  
# Display activity details
display_activity_details() {
    local activity="$1"
    local activity_id=$(echo "$activity" | jq -r '.data.id')
    local activity_status=$(echo "$activity" | jq -r '.data.attributes.status')
    local substatus=$(echo "$activity" | jq -r '.data.attributes.subStatus')
    local created=$(echo "$activity" | jq -r '.data.attributes.createdDateTime')
    local completed=$(echo "$activity" | jq -r '.data.attributes.completedDateTime // "N/A"')
    local download_url=$(echo "$activity" | jq -r '.data.attributes.downloadUrl // empty')
    echo ""
    echo "Activity Details:"
    echo "  Activity ID:      $activity_id"
    echo "  Status:           $activity_status"
    echo "  Sub-status:       $substatus"
    echo "  Created:          $created"
    echo "  Completed:        $completed"
    if [[ -n "$download_url" ]]; then
        echo "  Report Available: Yes"
    fi
}
  
# Download activity report
download_activity_report() {
    local download_url="$1"
    local output_file="$2"
    echo ""
    echo "Downloading activity report..."
    curl -s -L "$download_url" -o "$output_file"
    if [[ $? -eq 0 ]] && [[ -f "$output_file" ]]; then
        echo "Report downloaded successfully: $output_file"
        return 0
    else
        echo "Failed to download report"
        return 1
    fi
}
  
# Monitor activity with enhanced details
monitor_activity() {
    local access_token="$1"
    local activity_id="$2"
    local output_dir="$3"
    echo ""
    echo "Monitoring activity: $activity_id"
    echo "(Checking every 5 seconds...)"
    echo ""
    local check_count=0
    local max_checks=60  # 5 minutes max
    while [[ $check_count -lt $max_checks ]]; do
        sleep 5
        ((check_count++))
        local status_result=$(get_activity_status "$access_token" "$activity_id")
        if [[ $? -ne 0 ]]; then
            echo "Failed to check status. Stopping monitoring."
            return 1
        fi
        local current_status=$(echo "$status_result" | jq -r '.data.attributes.status')
        local current_substatus=$(echo "$status_result" | jq -r '.data.attributes.subStatus')
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] Status: $current_status - $current_substatus"
        # Check if completed (success or failure)
        if [[ "$current_status" == "COMPLETED" ]] || [[ "$current_status" == "FAILED" ]]; then
            echo ""
            display_activity_details "$status_result"
            # Check for download URL
            local download_url=$(echo "$status_result" | jq -r '.data.attributes.downloadUrl // empty')
            if [[ -n "$download_url" ]]; then
                echo ""
                echo -n "Download activity report? (y/n): "
                read download_choice
                if [[ "$download_choice" =~ ^[Yy]$ ]]; then
                    local report_file="${output_dir}/activity_${activity_id}_$(date +%Y%m%d_%H%M%S).csv"
                    download_activity_report "$download_url" "$report_file"
                fi
            fi
            return 0
        fi
    done
    echo ""
    echo "Monitoring timeout reached (5 minutes). Activity may still be processing."
    echo "You can check status later with activity ID: $activity_id"
    return 1
}
  
# Check existing activity status by ID
check_activity_by_id() {
    local access_token="$1"
    local output_dir="$2"
    echo ""
    echo "Check Activity Status"
    echo "===================="
    echo ""
    echo -n "Enter activity ID to check: "
    read activity_id
    if [[ -z "$activity_id" ]]; then
        echo "No activity ID provided, returning to main menu."
        return 0
    fi
    echo ""
    echo "Fetching activity status..."
    local status_result=$(get_activity_status "$access_token" "$activity_id")
    if [[ $? -ne 0 ]]; then
        echo "Failed to retrieve activity status."
        return
    fi
    display_activity_details "$status_result"
    # Check for download URL
    local download_url=$(echo "$status_result" | jq -r '.data.attributes.downloadUrl // empty')
    if [[ -n "$download_url" ]]; then
        echo ""
        echo -n "Download activity report? (y/n): "
        read download_choice
        if [[ "$download_choice" =~ ^[Yy]$ ]]; then
            local report_file="${output_dir}/activity_${activity_id}_$(date +%Y%m%d_%H%M%S).csv"
            download_activity_report "$download_url" "$report_file"
        fi
    fi
}
  
# Interactive MDM assignment menu
interactive_mdm_assignment() {
    local access_token="$1"
    local mdm_servers="$2"
    local output_dir="$3"
    while true; do
        echo ""
        echo "=================================="
        echo "MDM Device Assignment Tool"
        echo "=================================="
        echo ""
        echo "What would you like to do?"
        echo "  1. Assign devices to MDM server"
        echo "  2. Unassign devices from MDM server"
        echo "  3. Check activity status"
        echo "  4. Return to main menu"
        echo ""
        echo -n "Choose option (1-4): "
        read action_choice
        if [[ "$action_choice" == "4" ]]; then
            echo ""
            echo "Returning to main menu..."
            main
            return 0
        fi
        if [[ "$action_choice" == "3" ]]; then
            check_activity_by_id "$access_token" "$output_dir"
            continue
        fi
        if [[ "$action_choice" == "1" ]]; then
            # Assign devices
            echo ""
            echo "Available MDM Servers:"
            echo "$mdm_servers" | jq -r '.data[] | "  \(.id) - \(.attributes.serverName)"'
            echo ""
            echo -n "Enter MDM Server ID to assign devices to: "
            read mdm_server_id
            # Validate MDM server ID
            local server_exists=$(echo "$mdm_servers" | jq -r --arg id "$mdm_server_id" '.data[] | select(.id == $id) | .id')
            if [[ -z "$server_exists" ]]; then
                echo "Error: Invalid MDM Server ID"
                continue
            fi
            echo ""
            echo "Enter device IDs (serial numbers):"
            echo "  Options:"
            echo "    1. Comma-separated list (e.g., SERIAL1,SERIAL2,SERIAL3)"
            echo "    2. One per line (empty line to finish)"
            echo ""
            echo -n "Choose input method (1 or 2): "
            read input_method
            local device_ids=()
            if [[ "$input_method" == "1" ]]; then
                echo -n "Enter comma-separated device IDs: "
                read device_input
                # Split by comma and trim whitespace
                IFS=',' read -rA temp_array <<< "$device_input"
                for device_id in "${temp_array[@]}"; do
                    # Trim leading/trailing whitespace
                    device_id=$(echo "$device_id" | xargs)
                    if [[ -n "$device_id" ]]; then
                        device_ids+=("$device_id")
                    fi
                done
            else
                echo "Enter device IDs (one per line, empty line to finish):"
                while true; do
                    echo -n "Device ID: "
                    read device_id
                    if [[ -z "$device_id" ]]; then
                        break
                    fi
                    device_ids+=("$device_id")
                done
            fi
            if [[ ${#device_ids[@]} -eq 0 ]]; then
                echo "No devices specified. Canceling."
                continue
            fi
            echo ""
            echo "Devices to assign (${#device_ids[@]} total):"
            for device_id in "${device_ids[@]}"; do
                echo "  - $device_id"
            done
            echo ""
            echo -n "Proceed with assignment? (y/n): "
            read confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Assignment canceled."
                continue
            fi
            echo ""
            echo "Assigning ${#device_ids[@]} device(s) to MDM server $mdm_server_id..."
            local result=$(assign_devices_to_mdm "$access_token" "$mdm_server_id" "${device_ids[@]}")
            if [[ $? -eq 0 ]]; then
                local activity_id=$(echo "$result" | jq -r '.data.id')
                display_activity_details "$result"
                echo ""
                echo -n "Monitor assignment progress? (y/n): "
                read monitor_progress
                if [[ "$monitor_progress" =~ ^[Yy]$ ]]; then
                    monitor_activity "$access_token" "$activity_id" "$output_dir"
                else
                    echo "Activity ID for later reference: $activity_id"
                fi
            else
                echo "Failed to assign devices."
            fi
        elif [[ "$action_choice" == "2" ]]; then
            # Unassign devices
            echo ""
            echo "Enter device IDs (serial numbers) to unassign:"
            echo "  Options:"
            echo "    1. Comma-separated list (e.g., SERIAL1,SERIAL2,SERIAL3)"
            echo "    2. One per line (empty line to finish)"
            echo ""
            echo -n "Choose input method (1 or 2): "
            read input_method
            local device_ids=()
            if [[ "$input_method" == "1" ]]; then
                echo -n "Enter comma-separated device IDs: "
                read device_input
                # Split by comma and trim whitespace
                IFS=',' read -rA temp_array <<< "$device_input"
                for device_id in "${temp_array[@]}"; do
                    # Trim leading/trailing whitespace
                    device_id=$(echo "$device_id" | xargs)
                    if [[ -n "$device_id" ]]; then
                        device_ids+=("$device_id")
                    fi
                done
            else
                echo "Enter device IDs (one per line, empty line to finish):"
                while true; do
                    echo -n "Device ID: "
                    read device_id
                    if [[ -z "$device_id" ]]; then
                        break
                    fi
                    device_ids+=("$device_id")
                done
            fi
            if [[ ${#device_ids[@]} -eq 0 ]]; then
                echo "No devices specified. Canceling."
                continue
            fi
            echo ""
            echo "Devices to unassign (${#device_ids[@]} total):"
            for device_id in "${device_ids[@]}"; do
                echo "  - $device_id"
            done
            echo ""
            echo -n "Proceed with unassignment? (y/n): "
            read confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Unassignment canceled."
                continue
            fi
            echo ""
            echo "Unassigning ${#device_ids[@]} device(s) from MDM server..."
            local result=$(unassign_devices_from_mdm "$access_token" "${device_ids[@]}")
            if [[ $? -eq 0 ]]; then
                local activity_id=$(echo "$result" | jq -r '.data.id')
                display_activity_details "$result"
                echo ""
                echo -n "Monitor unassignment progress? (y/n): "
                read monitor_progress
                if [[ "$monitor_progress" =~ ^[Yy]$ ]]; then
                    monitor_activity "$access_token" "$activity_id" "$output_dir"
                else
                    echo "Activity ID for later reference: $activity_id"
                fi
            else
                echo "Failed to unassign devices."
            fi
        else
            echo "Invalid option."
        fi
    done
}
  
# Display MDM servers
select_mdm_servers_interactive() {
    local servers="$1"

    local server_count=$(echo "$servers" | jq '.data | length')
    if [[ "$server_count" -eq 0 ]]; then
        echo "ERROR:NO_SERVERS"
        return
    fi

    echo "" >&2
    echo "Available MDM Servers:" >&2
    echo "======================" >&2
    echo "$servers" | jq -r '.data[] | "  \(.id) - \(.attributes.serverName)"' >&2
    echo "" >&2

    echo "Enter MDM Server IDs to export from" >&2
    echo "  - Comma-separated (e.g. ID1,ID2)" >&2
    echo "  - Press Enter to cancel" >&2
    echo "" >&2
    echo -n "MDM Server IDs: " >&2
    read input

    [[ -z "$input" ]] && echo "CANCEL" && return

    local selected=()

    IFS=',' read -rA ids <<< "$input"
    for id in "${ids[@]}"; do
        id=$(echo "$id" | xargs)
        [[ -z "$id" ]] && continue

        local exists=$(echo "$servers" | jq -r --arg id "$id" '.data[] | select(.id == $id) | .id')
        if [[ -n "$exists" ]]; then
            selected+=("$id")
        else
            echo "Warning: Invalid MDM Server ID skipped: $id" >&2
        fi
    done

    if [[ "${#selected[@]}" -eq 0 ]]; then
        echo "ERROR:NO_VALID_SELECTION"
        return
    fi

    # stdout output
    echo "SELECTED:${selected[*]}"
}
  
show_main_menu() {
    echo ""
    echo ""

    # Show main menu
    echo "=================================="
    echo "             Main Menu"
    echo "=================================="
    echo ""
    echo "  1. Export devices from MDM server(s)"
    echo "  2. Manage MDM device assignments"
    echo "  3. Check activity status"
    echo "  4. Exit"
    echo ""
    echo -n "Choose option (1-4): "
    read main_choice
    
    if [[ "$main_choice" == "4" ]]; then
        echo "Goodbye!"
        exit 0
    fi
    
    # Fetch MDM servers for most operations
    echo ""
    echo "Fetching MDM servers..."
    MDM_SERVERS=$(fetch_mdm_servers "$ACCESS_TOKEN")
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Could not fetch MDM servers."
        exit 1
    fi
    
    if [[ "$main_choice" == "1" ]]; then
        # Ensure output directory is set for export
        if [[ -z "$OUTPUT_DIR" ]]; then
            echo ""
            echo -n "Enter output directory (press Enter for current directory): "
            read OUTPUT_DIR
            if [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="."
            fi
            OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
            echo "Output directory: $OUTPUT_DIR"
            echo ""
        fi
        
        # NOW create the directory
        create_output_directory "$OUTPUT_DIR"
        
        export_devices_with_filter "$ACCESS_TOKEN" "$MDM_SERVERS" "$OUTPUT_DIR"
        
    elif [[ "$main_choice" == "2" ]]; then
        # For assignments, set a default if not set (for activity reports)
        if [[ -z "$OUTPUT_DIR" ]]; then
            OUTPUT_DIR="$HOME/Downloads"
            echo ""
            echo "Using default directory for activity reports: $OUTPUT_DIR"
            echo ""
        fi
        
        # NOW create the directory
        create_output_directory "$OUTPUT_DIR"
        
        interactive_mdm_assignment "$ACCESS_TOKEN" "$MDM_SERVERS" "$OUTPUT_DIR"
        
    elif [[ "$main_choice" == "3" ]]; then
        # For checking activity status, set default if not set
        if [[ -z "$OUTPUT_DIR" ]]; then
            OUTPUT_DIR="$HOME/Downloads"
            echo ""
            echo "Using default directory for downloads: $OUTPUT_DIR"
            echo ""
        fi
        
        # NOW create the directory
        create_output_directory "$OUTPUT_DIR"
        
        check_activity_by_id "$ACCESS_TOKEN" "$OUTPUT_DIR"
        
    else
        echo "Invalid option."
        exit 1
    fi
    
    echo ""
    echo "Done!"
}
# ============================================================================
# MAIN SCRIPT
# ============================================================================
  
main() {
    echo "Apple School Manager API - Device Management Tool"
    echo "================================================="
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Allow command line arguments to override
    if [[ -n "$1" ]]; then
        CLIENT_ASSERTION="$1"
    fi
    if [[ -n "$2" ]]; then
        CLIENT_ID="$2"
    fi
    if [[ -n "$3" ]]; then
        OUTPUT_DIR="$3"
    fi
    
    # Configure Apple Manager settings
    configure_apple_manager
    
    # Prompt for any missing variables
    prompt_for_variables
    
    # Get access token (DON'T create output directory here)
    ACCESS_TOKEN=$(get_access_token "$CLIENT_ASSERTION" "$CLIENT_ID" "$SCOPE")
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        echo "Error: Failed to get access token"
        exit 1
    fi
    
    echo ""
    
    # Show main menu
    show_main_menu
}
  
# Run main function
main "$@"
