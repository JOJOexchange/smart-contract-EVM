// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import "../../src/libraries/Types.sol";

library EIP712Test {
    // add this to be excluded from coverage report
    function test() public { }

    function _structHash(Types.Order memory order) internal pure returns (bytes32 structHash) {
        bytes32 orderTypeHash = Types.ORDER_TYPEHASH;
        assembly {
            let start := sub(order, 32)
            let tmp := mload(start)
            // 192 = (1 + 5) * 32
            // [0...32)   bytes: EIP712_ORDER_TYPE
            // [32...192) bytes: order
            mstore(start, orderTypeHash)
            structHash := keccak256(start, 192)
            mstore(start, tmp)
        }
    }

    function _buildDomainSeparator(
        string memory name,
        string memory version,
        address verifyingContract
    )
        internal
        view
        returns (bytes32)
    {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(typeHash, hashedName, hashedVersion, block.chainid, verifyingContract));
    }

    function _hashTypedDataV4(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
