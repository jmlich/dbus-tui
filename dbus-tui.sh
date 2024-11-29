#!/bin/bash
# author: Jozef Mlich <jmlich83@gmail.com>
# SPDX-License-Identifier: BSD-3-Clause

#BUS_TYPE="--system"
#BUS_NAME="org.bluez"
#BUS_OBJECT="/org/bluez/hci0"
#BUS_INTERFACE="org.bluez.Adapter1"

BUS_TYPE=""
BUS_NAME=""
BUS_OBJECT=""
BUS_INTERFACE=""

LAST_CONFIG_FN="/tmp/dbus-tui.config.sh"

if [ -f "$LAST_CONFIG_FN" ]; then
    source "$LAST_CONFIG_FN" || echo "Cannot load $LAST_CONFIG_FN" >&2
fi

function select_bus_type() {

    exec 3>&1
    ret=0

    declare -a dialog_args=(1 "System" 2 "User")

    declare -a choice_to_opt=(
        [1]="--system" \
        [2]="--user" \
    )

    choice=$(
    dialog --clear --backtitle "Choose D-BUS Type" \
        --title "Options" \
        --menu "Choose one of the following options:" 15 50 2 \
        "${dialog_args[@]}" \
         2>&1 1>&3
    ) || ret=$? # show dialog and pass non zero return code to ret

    exec 3>&-

    if [ -z "$choice" ]; then
        return 1
    fi

    BUS_TYPE="${choice_to_opt[$choice]}"
    return "$ret"
}


function select_bus() {

    declare -a dialog_args=()

    # Read the output directly into dialog_args
    while IFS=$'\t' read -r bus_name bus_process; do
        # Directly add bus name and process to dialog_args
        dialog_args+=("$bus_name" "$bus_process")
    done < <(busctl "$BUS_TYPE" --json=short | jq -r '.[] | [.name, (.unit // "(empty)")] | @tsv')

    if [ "${#dialog_args[@]}" -eq 0 ]; then
        echo "Error: No bus to display in dialog" >&2
        unset BUS_TYPE
        return 2;
    fi

    # Display the dialog menu
    exec 3>&1
    BUS_NAME=$(dialog --clear --backtitle "Select a service" \
                   --title "Services and Processes" \
                   --menu "Choose a service:" 0 0 0 \
                   "${dialog_args[@]}" \
                   2>&1 1>&3)
    exec 3>&-

    if [ -z "$BUS_NAME" ]; then
        unset BUS_TYPE
        return 1
    fi

}

function select_object() {
    readarray -t bus_objects < <(busctl "$BUS_TYPE" tree --list "$BUS_NAME")

    declare -a dialog_args=()
    for i in "${!bus_objects[@]}"; do
        dialog_args+=("$i" "${bus_objects[$i]}")
    done

    if [ "${#dialog_args[@]}" -eq 0 ]; then
        echo "Error: No object to display in dialog" >&2
        unset BUS_NAME
        return 2;
    fi

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select a D-Bus object" \
                       --title "D-Bus Objects" \
                       --menu "Choose an object:" 0 0 0 \
                       "${dialog_args[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    if [[ -z "$selection" ]]; then
        unset BUS_NAME
        return 1
    fi

    BUS_OBJECT="${bus_objects[$selection]}"
}

function select_interface() {

    IFS=$'\n' read -r -d '' -a interfaces < <(busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT" | xmllint --xpath '//interface/@name' - 2> /dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')

    # Prepare dialog arguments
    declare -a dialog_args=()
    for i in "${!interfaces[@]}"; do
        dialog_args+=("$i" "${interfaces[$i]}")
    done

    if [ "${#dialog_args[@]}" -eq 0 ]; then
        echo "Error: No interface to display in dialog" >&2
        unset BUS_OBJECT
        return 2;
    fi

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select an interface" \
                       --title "D-Bus Interfaces" \
                       --menu "Choose an interface:" 0 0 0 \
                       "${dialog_args[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    if [ -z "$selection" ]; then
        unset BUS_OBJECT
        return 1
    fi

    # Set the BUS_INTERFACE variable based on the selection
    BUS_INTERFACE="${interfaces[$selection]}"
}

function write_property() {
    data_type=${1:0:1}
    default_value=${1:2}
    exec 3>&1
    value=$(dialog --clear \
                   --title "Write $BUS_PROPERTY" \
                   --inputbox "Please enter some text:" \
                   0 0 "$default_value" \
                   2>&1 1>&3)
    ret="$?"
    exec 3>&-
    if [ "$ret" -ne 0]; then
        return 1
    fi

    if [ -z "$value" ]; then
        return 1
    fi

    busctl "$BUS_TYPE" set-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY" "$data_type" "$value"

}

function call_method() {
    local method_signature="$1"

    declare -a dialog_args=()
    types=""

    show_output=false

    i=1
    while read -r snippet; do
        direction=$(xmllint --xpath '//arg/@direction' - 2>/dev/null  <<< "$snippet" | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}') #'
        if [ "$direction" = "out" ]; then
            show_output=true
            continue
        fi
        name=$(xmllint --xpath '//arg/@name' - 2>/dev/null  <<< "$snippet" | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}') #'
        type=$(xmllint --xpath '//arg/@type' - 2>/dev/null  <<< "$snippet" | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}') #'
        dialog_args+=("${name:-(undefined)} ($type)" $i 1 "" $i 20 30 0)
        types+="$type"
        i=$((i + 1))
    done < <(xmllint --xpath '//method/arg' - 2>/dev/null  <<< "$method_signature" && printf '\0')

    if [ "${#dialog_args[@]}" -eq 0 ]; then
        output=$(busctl "$BUS_TYPE" call "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_METHOD")
        if [ "$show_output" = "true" ]; then
            dialog --msgbox "$output" 10 50
        fi
        return $?
    fi

    local num_rows=$((i + 6))
    local ret
    exec 3>&1
    output=$(dialog --clear \
       --title "Call $BUS_METHOD" \
       --form "Enter the details:" \
       $num_rows 50 $i \
       "${dialog_args[@]}" \
       2>&1 1>&3) || ret=$?
    exec 3>&-

    if [ "0$ret" -ne 0 ]; then # Cancel was pressed
        return 1
    fi

    readarray -t values <<< "$output"
    output=$(busctl "$BUS_TYPE" call "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_METHOD" "$types" "${values[@]}")

    if [ "$show_output" = "true" ]; then
        dialog --msgbox "$output" 10 50
    fi

}

function select_method_or_property() {
    # Retrieve methods and properties, store them into arrays
    local interface
    interface="$(busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT")"
    IFS=$'\n' read -r -d '' -a methods < <(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/method/@name" - <<< "$interface" 2>/dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')
    IFS=$'\n' read -r -d '' -a properties < <(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/property/@name" - <<< "$interface" 2>/dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')
    IFS=$'\n' read -r -d '' -a signals < <(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/signal/@name" - <<< "$interface" 2>/dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')

    # Prepare dialog menu items
    declare -a dialog_items=()
    local index=0
    for method in "${methods[@]}"; do
        dialog_items+=("$index" "Method: $method")
        ((index++))
    done
    for property in "${properties[@]}"; do
        dialog_items+=("$index" "Property: $property")
        ((index++))
    done

    for signal in "${signals[@]}"; do
        dialog_items+=("$index" "Signal: $signal")
        ((index++))
    done

    if [ "${#dialog_items[@]}" -eq 0 ]; then
        echo "Error: No method/property/signal to display in dialog" >&2
        unset BUS_INTERFACE
        return 2;
    fi

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select a Method or Property" \
                       --title "Methods and Properties" \
                       --menu "Choose an item:" 0 0 0 \
                       "${dialog_items[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    # Process the selection
    if [ -z "$selection" ]; then
        unset BUS_INTERFACE
        return 1
    elif [ "$selection" -lt "${#methods[@]}" ]; then
        BUS_METHOD=${methods[$selection]}
        call_method "$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/method[@name=\"$BUS_METHOD\"]" - <<< "$interface")"

    elif [ $(( selection - ${#methods[@]} )) -lt "${#properties[@]}" ]; then
        local property_idx=$(( selection - ${#methods[@]} ))
        BUS_PROPERTY="${properties[$property_idx]}"
        property_signature="$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/property[@name=\"$BUS_PROPERTY\"]" - <<< "$interface")"

        property_access=$(xmllint --xpath "string(/property/@access)" - <<< "$property_signature") #"

        case "$property_access" in
            "readwrite")
            ;&
            "write")
                extra_args=("--extra-button" "--extra-label" "Write")
            ;;
        esac

        property_value="$(busctl "$BUS_TYPE" get-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY")"

        dialog ${extra_args[@]} --title "Selected Property: $BUS_PROPERTY" --msgbox "$property_signature\n\n$property_value"  0 0
        ret=$?
        if [ "$ret" -eq 3 ]; then
            write_property "$property_value"
#        else
#            echo busctl "$BUS_TYPE" get-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY" >&2
#            echo $property_value >&2
#            exit
    fi

    else
        local signal_idx=$(( selection - ${#methods[@]} - ${#properties[@]} ))
        BUS_SIGNAL="${signals[signal_idx]}"
        signal_signature="$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/signal[@name=\"$BUS_SIGNAL\"]" - <<< "$interface")"
        dialog --title "Selected Signal $BUS_SIGNAL" --msgbox "FIXME: emit signal?\n\n$signal_signature" 0 0

    fi
}

function cleanup() {
    declare -p BUS_TYPE BUS_NAME BUS_OBJECT BUS_INTERFACE > "$LAST_CONFIG_FN"
    cat "$LAST_CONFIG_FN"
}

trap cleanup EXIT

declare -a commands=('dialog' 'xmllint' 'jq')

for cmd in "${commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: dependency '$cmd' is missing" >&2
        exit 1
    fi
done

while /bin/true; do

    if [ -z "$BUS_TYPE" ]; then
        if ! select_bus_type; then
            break
        fi
    fi

    if [ -z "$BUS_NAME" ]; then
        if ! select_bus; then
            continue
        fi
    fi

    if [ -z "$BUS_OBJECT" ]; then
        if ! select_object; then
            continue;
        fi
    fi

    if [ -z "$BUS_INTERFACE" ]; then
        if ! select_interface; then
            continue
        fi
    fi

    select_method_or_property

    #busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT"|xmllint  -format -

done
