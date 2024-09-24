#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Setting up network and communication with someip daemon via SIL Kit Adapter TAP..."

# check if user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root / via sudo!"
    exit 1
fi

#Make a temporary fifo to use as std:cin which is not fd#0 (this shell's std:cin) to prevent unintended closure of the background-launched processes
tmp_fifo=$(mktemp -u)
mkfifo $tmp_fifo
exec 3<>$tmp_fifo
rm $tmp_fifo

killall -w -q -15 SilKitAdapterTap &> /dev/null
echo "SilKitAdapterTap has been stopped"

echo "Recreating tap_demo_ns network namespace"
if test -f "/var/run/netns/tap_demo_ns"; then
    ip netns delete tap_demo_ns
fi

echo "Creating tap device calc_tap"
ip tuntap add dev calc_tap mode tap

echo "Starting SilKitAdapterTap..."
<&3 /mnt/d/shashi/vector/Techday/VIC_2024/silkit/SilKit-Adapters/bin/SilKitAdapterTap --name 'CalcServerTap' --tap-name 'calc_tap' --registry-uri 'silkit://172.17.89.75:8501' --network 'Eth1' &> /$SCRIPT_DIR/SilKitAdapterTap.out &
sleep 1

timeout 30s grep -q 'Press enter to stop the process...' <(tail -f /$SCRIPT_DIR/SilKitAdapterTap.out) || exit 1
echo "SilKitAdapterTap has been started"

# Hint: It is important to establish the connection to the the adapter before moving the tap device to its separate namespace
echo "Moving tap device 'calc_tap' to network namespace 'tap_demo_ns'"
ip netns add tap_demo_ns
ip link set calc_tap netns tap_demo_ns

echo "Configuring tap device 'calc_tap'"
# Hint: The IP address can be set to anything as long as it is in the same network as the echo device which is pinged
ip -netns tap_demo_ns addr add 192.168.7.2/16 dev calc_tap
ip -netns tap_demo_ns link set calc_tap up
#172.17.89.75
#192.168.7.2


# stop someip daemon
killall -w -q -15 someipd_posix &> /dev/null
echo "someip daemon has been stopped."

# start someip daemon
cd $SCRIPT_DIR/tools/someipd_posix/
nohup bash -c "nsenter --net=/var/run/netns/tap_demo_ns /"$SCRIPT_DIR"/tools/someipd_posix/bin/someipd_posix -c /"$SCRIPT_DIR"/someipd-posix.json & disown %1" &> $SCRIPT_DIR/someipd_posix.out
sleep 2
echo "someip daemon has been started."
