// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IBrevisProof.sol";
// import "../../lib/Lib.sol";

abstract contract BrevisApp {
    IBrevisProof public brevisProof;

    constructor(IBrevisProof _brevisProof) {
        brevisProof = _brevisProof;
    }

    function validateRequest(
        bytes32 _requestId,
        uint64 _chainId,
        Brevis.ExtractInfos memory _extractInfos
    ) public view virtual returns (bool) {
        brevisProof.validateRequest(_requestId, _chainId, _extractInfos);
        return true;
    }

    function brevisCallback(bytes32 _requestId, bytes calldata _appCircuitOutput) external {
        (bytes32 appCommitHash, bytes32 appVkHash) = IBrevisProof(brevisProof).getProofAppData(_requestId);
        require(appCommitHash == keccak256(_appCircuitOutput), "failed to open output commitment");
        handleProofResult(_requestId, appVkHash, _appCircuitOutput);
    }

    function handleProofResult(bytes32 _requestId, bytes32 _vkHash, bytes calldata _appCircuitOutput) internal virtual {
        // to be overrided by custom app
    }

    function brevisBatchCallback(
        uint64 _chainId,
        Brevis.ProofData[] calldata _proofDataArray,
        bytes[] calldata _appCircuitOutputs
    ) external {
        require(_proofDataArray.length == _appCircuitOutputs.length, "length not match");
        IBrevisProof(brevisProof).mustValidateRequests(_chainId, _proofDataArray);
        for (uint i = 0; i < _proofDataArray.length; i++) {
            require(
                _proofDataArray[i].appCommitHash == keccak256(_appCircuitOutputs[i]),
                "failed to open output commitment"
            );
            handleProofResult(_proofDataArray[i].commitHash, _proofDataArray[i].appVkHash, _appCircuitOutputs[i]);
        }
    }

    // handle request in AggProof case, called by biz side
    function singleRun(
        uint64 _chainId,
        Brevis.ProofData calldata _proofData,
        bytes32 _merkleRoot,
        bytes32[] calldata _merkleProof,
        uint8 _nodeIndex,
        bytes calldata _appCircuitOutput
    ) external {
        IBrevisProof(brevisProof).mustValidateRequest(_chainId, _proofData, _merkleRoot, _merkleProof, _nodeIndex);
        require(_proofData.appCommitHash == keccak256(_appCircuitOutput), "failed to open output commitment");
        handleProofResult(_proofData.commitHash, _proofData.appVkHash, _appCircuitOutput);
    }
}
