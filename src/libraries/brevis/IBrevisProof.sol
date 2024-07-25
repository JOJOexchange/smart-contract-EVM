// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./lib/Lib.sol";

interface IBrevisProof {
    function submitProof(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs,
        bool _withAppProof
    ) external returns (bytes32 _requestId);

    function hasProof(bytes32 _requestId) external view returns (bool);

    // used by contract app
    function validateRequest(bytes32 _requestId, uint64 _chainId, Brevis.ExtractInfos memory _info) external view;

    function getProofData(bytes32 _requestId) external view returns (Brevis.ProofData memory);

    // return appCommitHash and appVkHash
    function getProofAppData(bytes32 _requestId) external view returns (bytes32, bytes32);

    function mustValidateRequest(
        uint64 _chainId,
        Brevis.ProofData calldata _proofData,
        bytes32 _merkleRoot,
        bytes32[] calldata _merkleProof,
        uint8 _nodeIndex
    ) external view;

    function mustValidateRequests(uint64 _chainId, Brevis.ProofData[] calldata _proofDataArray) external view;

    function mustSubmitAggProof(
        uint64 _chainId,
        bytes32[] calldata _requestIds,
        bytes calldata _proofWithPubInputs
    ) external;
}
