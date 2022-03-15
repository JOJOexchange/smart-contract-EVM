pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../utils/SignedDecimalMath.sol";

contract JOJOBase is Ownable, ReentrancyGuard {
    address underlyingAsset; // IERC20
    address insurance;

    struct riskParams {
        // liquidate when netValue/exposure < liquidationThreshold
        // the lower liquidationThreshold, leverage multiplier higher
        uint256 liquidationThreshold;
        uint256 liquidationPriceOff;
        uint256 insuranceFeeRate;
        uint256 maxPaperSupply;
        int256 fundingRatio;
        address markPriceSource;
    }
    mapping(address => bool) public perpRegister;
    mapping(address => riskParams) public perpRiskParams;

    modifier perpRegistered(address perp) {
        require(perpRegister[perp], "PERP NOT REGISTERED");
        _;
    }

    modifier perpNotRegistered(address perp) {
        require(!perpRegister[perp], "PERP REGISTERED");
        _;
    }

    function getFundingRatio(address perpetualAddress)
        external
        view
        perpRegistered(perpetualAddress)
        returns (int256)
    {
        return perpRiskParams[perpetualAddress].fundingRatio;
    }

    function setFundingRatio(
        address[] calldata perpList,
        int256[] calldata ratioList
    ) external onlyOwner {
        for (uint256 i = 0; i < perpList.length; i++) {
            riskParams storage param = perpRiskParams[perpList[i]];
            param.fundingRatio = ratioList[i];
        }
    }

    function registerNewPerp(address perp, riskParams calldata param) external onlyOwner perpNotRegistered(perp){
        perpRiskParams[perp] = param;
    }

}
