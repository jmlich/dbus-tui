#!/bin/bash
# author: Jozef Mlich <jmlich83@gmail.com>
# SPDX-License-Identifier: BSD-3-Clause

#BUS_TYPE="--system"
#BUS_NAME="org.bluez"
#BUS_OBJECT="/org/bluez/hci0"
#BUS_INTERFACE="org.bluez.Adapter1"

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
        method_signature="$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/method[@name=\"$BUS_METHOD\"]" - <<< "$interface")"

        dialog --title "Selected Method: $BUS_METHOD" --msgbox "FIXME: create method dialog and show response?\n\n$method_signature" 0 0
    elif [ $(( selection - ${#methods[@]} )) -lt "${#properties[@]}" ]; then
        local property_idx=$(( selection - ${#methods[@]} ))
        BUS_PROPERTY="${properties[$property_idx]}"
        property_signature="$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/property[@name=\"$BUS_PROPERTY\"]" - <<< "$interface")"

        # FIXME: Can be also write property
        echo busctl "$BUS_TYPE" get-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY" >&2
        property_value="$(busctl "$BUS_TYPE" get-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY")"
        dialog --title "Selected Property: $BUS_PROPERTY" --msgbox "$property_signature\n\n$property_value" 0 0
    else
        local signal_idx=$(( selection - ${#methods[@]} - ${#properties[@]} ))
        BUS_SIGNAL="${signals[signal_idx]}"
        signal_signature="$(xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/signal[@name=\"$BUS_SIGNAL\"]" - <<< "$interface")"
        dialog --title "Selected Signal $BUS_SIGNAL" --msgbox "FIXME: emit signal?\n\n$signal_signature" 0 0

    fi
}

function cleanup() {
    echo "BUS_TYPE=\"$BUS_TYPE\"; BUS_NAME=\"$BUS_NAME\"; BUS_OBJECT=\"$BUS_OBJECT\"; BUS_INTERFACE=\"$BUS_INTERFACE\";"
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
