/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@moonwell/MToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IController {
    function claimReward(address[] memory holders, MToken[] memory mTokens) external;
}

contract JwarpMUSDCSubaccount {
    address public owner;
    address public controller;
    address public factory;
    address public mUSDC;
    address public well;
    address public usdc;
    bool public initialized;

    using SafeERC20 for IERC20;

    // ========== modifier ==========

    modifier onlyFactory() {
        require(factory == msg.sender, "Ownable: caller is not the factory");
        _;
    }

    modifier onlyFactoryAndOwner() {
        require(factory == msg.sender || msg.sender == owner, "Ownable: caller is not the owner or factory");
        _;
    }

    // ========== functions ==========

    function init(address _owner, address _factory, address _controller, address _mUSDC, address _well, address _usdc) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
        factory = _factory;
        controller = _controller;
        mUSDC = _mUSDC;
        well = _well;
        usdc = _usdc;
    }

    function claimReward() external onlyFactory {
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = MToken(mUSDC);
        IController(controller).claimReward(holders, mTokens);
        IERC20(usdc).safeTransfer(owner, IERC20(usdc).balanceOf(address(this)));
        IERC20(well).safeTransfer(owner, IERC20(well).balanceOf(address(this)));
    }

    function withdraw(uint256 amount) external onlyFactory {
        IERC20(mUSDC).safeTransfer(owner, amount);
    }

    function transferMUSDC(address to, uint256 amount) external onlyFactoryAndOwner {
        // do not call this function by yourself!!!!
        IERC20(mUSDC).safeTransfer(to, amount);
    }
}
