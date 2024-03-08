#!/bin/bash

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

    BUS_TYPE="${choice_to_opt[$choice]}"
}


function select_bus() {

    declare -a dialog_args=()

    # Read the output directly into dialog_args
    while IFS=$'\t' read -r bus_name bus_process; do
        # Directly add bus name and process to dialog_args
        dialog_args+=("$bus_name" "$bus_process")
    done < <(busctl "$BUS_TYPE" --json=short | jq -r '.[] | [.name, (.unit // "(empty)")] | @tsv')

    # Display the dialog menu
    exec 3>&1
    BUS_NAME=$(dialog --clear --backtitle "Select a service" \
                   --title "Services and Processes" \
                   --menu "Choose a service:" 0 0 0 \
                   "${dialog_args[@]}" \
                   2>&1 1>&3)
    exec 3>&-

}

function select_object() {
    readarray -t bus_objects < <(busctl --system tree --list "$BUS_NAME")

    declare -a dialog_args=()
    for i in "${!bus_objects[@]}"; do
        dialog_args+=("$i" "${bus_objects[$i]}")
    done

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select a D-Bus object" \
                       --title "D-Bus Objects" \
                       --menu "Choose an object:" 0 0 0 \
                       "${dialog_args[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    BUS_OBJECT="${bus_objects[$selection]}"
}

function select_interface() {

    IFS=$'\n' read -r -d '' -a interfaces < <(busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT" | xmllint --xpath '//interface/@name' - | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')

    # Prepare dialog arguments
    declare -a dialog_args=()
    for i in "${!interfaces[@]}"; do
        dialog_args+=("$i" "${interfaces[$i]}")
    done

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select an interface" \
                       --title "D-Bus Interfaces" \
                       --menu "Choose an interface:" 0 0 0 \
                       "${dialog_args[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    # Set the BUS_INTERFACE variable based on the selection
    BUS_INTERFACE="${interfaces[$selection]}"
}

function select_method_or_property() {
    # Retrieve methods and properties, store them into arrays
    IFS=$'\n' read -r -d '' -a methods < <(busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT" | xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/method/@name" - 2>/dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')
    IFS=$'\n' read -r -d '' -a properties < <(busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT" | xmllint --xpath "//interface[@name=\"$BUS_INTERFACE\"]/property/@name" - 2>/dev/null | awk -F'"' '{for (i=2; i<=NF; i+=2) print $(i)}' && printf '\0')

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
        echo "No selection made."
        return
    elif [ "$selection" -lt "${#methods[@]}" ]; then
        echo "Selected Method: ${methods[$selection]}"
    else
        local property_idx=$(( selection - ${#methods[@]} ))
        BUS_PROPERTY="${properties[$property_idx]}"
        echo "Selected Property: $BUS_PROPERTY"
        busctl "$BUS_TYPE" get-property "$BUS_NAME" "$BUS_OBJECT" "$BUS_INTERFACE" "$BUS_PROPERTY"
    fi
}

if ! command -v dialog &> /dev/null; then
    echo "Error: install dialog first" >&2
    exit 1
fi

if [ -z "$BUS_TYPE" ]; then
    select_bus_type
fi

if [ -z "$BUS_NAME" ]; then
    select_bus
fi

if [ -z "$BUS_OBJECT" ]; then
    select_object
fi

if [ -z "$BUS_INTERFACE" ]; then
    select_interface
fi


select_method_or_property

#echo BUS_TYPE=$BUS_TYPE BUS_NAME=$BUS_NAME BUS_OBJECT=$BUS_OBJECT BUS_INTERFACE=$BUS_INTERFACE
#busctl "$BUS_TYPE" --xml-interface introspect "$BUS_NAME" "$BUS_OBJECT"|xmllint  -format -
#set -x


