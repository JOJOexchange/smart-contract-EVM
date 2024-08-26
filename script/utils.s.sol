// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Script.sol";

library Utils {
    /**
     * @dev Logs the inputs of a function call.
     * @param inputs The inputs to log.
     */
    function logInputs(string[] memory inputs) public view {
        string memory concatenatedInputs = "";
        for (uint256 i = 0; i < inputs.length; i++) {
            concatenatedInputs = string(abi.encodePacked(concatenatedInputs, inputs[i], " "));
        }
        console.log(concatenatedInputs);
    }

    /**
     * @dev Converts an address to its string representation.
     * @param addr The address to convert.
     * @return The string representation of the address.
     */
    function addressToString(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @dev Converts bytes to a string without the '0x' prefix.
     * @param data The bytes to convert.
     * @return The string representation of the bytes.
     */
    function bytesToStringWithout0x(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[i * 2 + 1] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}