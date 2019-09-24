pragma solidity ^0.5.10;

import '../gelato_action_standards/GelatoActionsStandard.sol';
import '../../../gelato_dappInterfaces/gelato_DutchX/gelato_DutchX_standards/GelatoDutchXStandard.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract ActionDutchXSell is GelatoActionsStandard,
                             GelatoDutchXStandard,
                             ReentrancyGuard
{
    constructor(address _gelatoCore,
                address _dutchX,
                string _actionSignature,
                uint256 _actionGasStipend
    )
        public
        GelatoActionsStandard(_gelatoCore,
                              _dutchX,
                              _actionSignature,
                              _actionGasStipend
        )
        GelatoDutchXStandard(_dutchX)
    {}

    // SellCondition: token pair is traded on DutchX
    function conditionsFulfilled(bytes calldata _payload)
        public
        view
        returns(bool)
    {
        (address _sellToken,
         address _buyToken) = abi.decode(_payload, (address, address));
        if (dutchExchange.getAuctionIndex(_sellToken, _buyToken) == 0) {
            return false;
        } else {
            return true;
        }
    }

    // Action:
    function action(uint256 _executionClaimId,
                    address _executionClaimOwner,
                    address _sellToken,
                    address _buyToken,
                    uint256 _sellAmount
    )
        nonReentrant
        ERC20Allowance(_sellToken, _executionClaimOwner, _sellAmount)
        tokenPairIsTraded(_sellToken, _buyToken)
        public
        returns(bool,
                uint256 sellAuctionIndex,
                uint256 sellAmountAfterFee
        )
    {
        _standardActionChecks();
        require(conditionsFulfilled(_sellToken, buyToken),
            "ActionDutchXSell.action: tokens not traded on DutchX"
        );
        require(_buyToken != address(0),
            "ActionDutchXSell.action: _buyToken zero-value"
        );
        (success,
         sellAuctionIndex,
         sellAmountAfterFee) = _sellOnDutchX(_executionClaimId,
                                             _executionClaimOwner,
                                             _sellToken,
                                             _buyToken,
                                             _sellAmount
        );
        require(success,
            "ActionDutchXSell.action._sellOnDutchX failed"
        );
        return true;
    }
}
