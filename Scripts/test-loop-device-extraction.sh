#!/bin/bash

# Unit test for loop device extraction logic
# This tests the device detection and loop number extraction

echo "=== Loop Device Extraction Unit Tests ==="
echo

# Test function that simulates the extraction logic
test_loop_extraction() {
    local test_name="$1"
    local simulated_devices="$2"
    local expected_loop_num="$3"
    
    echo "Test: ${test_name}"
    echo "Input devices:"
    echo "${simulated_devices}"
    
    # Simulate the extraction logic from the main script
    MAPPER_DEVICES="${simulated_devices}"
    
    if [ -z "${MAPPER_DEVICES}" ]; then
        echo "Result: No mapper devices found!"
        echo "FAIL: Expected loop number ${expected_loop_num}"
        echo
        return 1
    fi
    
    # Get the first device to extract the loop number
    FIRST_DEVICE=$(echo "${MAPPER_DEVICES}" | head -n1)
    echo "First device: ${FIRST_DEVICE}"
    
    # Get the correct loop device number from the mapper devices
    MAPPER_LOOP_NUM=$(echo "${FIRST_DEVICE}" | sed 's/.*loop\([0-9]*\)p[0-9]*/\1/')
    echo "Extracted loop number: '${MAPPER_LOOP_NUM}'"
    
    # Verify the result
    if [ "${MAPPER_LOOP_NUM}" = "${expected_loop_num}" ]; then
        echo "PASS: Got expected loop number ${expected_loop_num}"
        
        # Also verify we can construct valid device paths
        DEVICE_P1="/dev/mapper/loop${MAPPER_LOOP_NUM}p1"
        DEVICE_P2="/dev/mapper/loop${MAPPER_LOOP_NUM}p2"
        echo "Would construct: ${DEVICE_P1} and ${DEVICE_P2}"
    else
        echo "FAIL: Expected '${expected_loop_num}' but got '${MAPPER_LOOP_NUM}'"
    fi
    echo
}

# Test 1: Standard case with two partitions
test_loop_extraction "Standard two partitions" \
"/dev/mapper/loop0p1
/dev/mapper/loop0p2" \
"0"

# Test 2: Different loop number
test_loop_extraction "Loop device 3" \
"/dev/mapper/loop3p1
/dev/mapper/loop3p2" \
"3"

# Test 3: Multiple digit loop number
test_loop_extraction "Double digit loop number" \
"/dev/mapper/loop12p1
/dev/mapper/loop12p2" \
"12"

# Test 4: Single partition (edge case)
test_loop_extraction "Single partition only" \
"/dev/mapper/loop5p1" \
"5"

# Test 5: Reverse order (p2 before p1)
test_loop_extraction "Reverse partition order" \
"/dev/mapper/loop7p2
/dev/mapper/loop7p1" \
"7"

# Test 6: Empty device list
test_loop_extraction "Empty device list" \
"" \
"should_fail"

# Test the actual ls command pattern matching
echo "=== Testing grep pattern ==="
echo "Testing pattern: grep -E \"loop[0-9]+p[12]$\""
echo

# Simulate various device names and test the pattern
test_patterns() {
    local device="$1"
    local should_match="$2"
    
    if echo "${device}" | grep -E "loop[0-9]+p[12]$" >/dev/null; then
        result="MATCHES"
    else
        result="NO MATCH"
    fi
    
    if [ "${should_match}" = "yes" -a "${result}" = "MATCHES" ] || 
       [ "${should_match}" = "no" -a "${result}" = "NO MATCH" ]; then
        status="PASS"
    else
        status="FAIL"
    fi
    
    printf "%-30s %-10s %s\n" "${device}" "${result}" "${status}"
}

echo "Device Name                    Result     Status"
echo "------------------------------------------------"
test_patterns "/dev/mapper/loop0p1" "yes"
test_patterns "/dev/mapper/loop0p2" "yes"
test_patterns "/dev/mapper/loop10p1" "yes"
test_patterns "/dev/mapper/loop0p3" "no"
test_patterns "/dev/mapper/loop0" "no"
test_patterns "/dev/mapper/loop0p1p1" "no"
test_patterns "/dev/mapper/sda1" "no"
test_patterns "/dev/mapper/control" "no"

echo
echo "=== Testing sed extraction pattern ==="
echo "Pattern: sed 's/.*loop\([0-9]*\)p[0-9]*/\1/'"
echo

test_sed_pattern() {
    local input="$1"
    local expected="$2"
    
    result=$(echo "${input}" | sed 's/.*loop\([0-9]*\)p[0-9]*/\1/')
    
    if [ "${result}" = "${expected}" ]; then
        status="PASS"
    else
        status="FAIL"
    fi
    
    printf "%-30s => %-5s %s\n" "${input}" "${result}" "${status}"
}

echo "Input                          => Result Status"
echo "------------------------------------------------"
test_sed_pattern "/dev/mapper/loop0p1" "0"
test_sed_pattern "/dev/mapper/loop0p2" "0"
test_sed_pattern "/dev/mapper/loop5p1" "5"
test_sed_pattern "/dev/mapper/loop12p2" "12"
test_sed_pattern "/dev/mapper/loop123p1" "123"

echo
echo "=== Summary ==="
echo "These tests verify that:"
echo "1. The device detection pattern correctly identifies loop device partitions"
echo "2. The sed extraction correctly extracts loop numbers from device paths"
echo "3. The script handles both single and double-digit loop numbers"
echo "4. The first device is used when multiple devices are present"