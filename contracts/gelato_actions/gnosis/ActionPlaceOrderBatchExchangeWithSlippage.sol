// "SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.6.10;
pragma experimental ABIEncoderV2;

import {ActionPlaceOrderBatchExchange} from "./ActionPlaceOrderBatchExchange.sol";
import {DataFlow} from "../../gelato_core/interfaces/IGelatoCore.sol";
import {IERC20} from "../../external/IERC20.sol";
import {SafeERC20} from "../../external/SafeERC20.sol";
import {SafeMath} from "../../external/SafeMath.sol";
import {IBatchExchange} from "../../dapp_interfaces/gnosis/IBatchExchange.sol";
import {Task} from "../../gelato_core/interfaces/IGelatoCore.sol";
import {IKyber} from "../../dapp_interfaces/kyber/IKyber.sol";

/// @title ActionPlaceOrderBatchExchangeWithSlippage
/// @author Luis Schliesske & Hilmar Orth
/// @notice Gelato Action that
///  1) Calculates buyAmout based on inputted slippage value,
///  2) withdraws funds form user's  EOA,
///  3) deposits on Batch Exchange,
///  4) Places order on batch exchange and
//   5) requests future withdraw on batch exchange
contract ActionPlaceOrderBatchExchangeWithSlippage is ActionPlaceOrderBatchExchange {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IKyber public immutable kyber;

    constructor(
        IBatchExchange _batchExchange,
        IKyber _kyberProxy
    )
        ActionPlaceOrderBatchExchange(_batchExchange)
        public
    {
        kyber = _kyberProxy;
    }

    /// @dev use this function to encode the data off-chain for the action data field
    function getActionData(
        address _origin,
        IERC20 _sellToken,
        uint128 _sellAmount,
        IERC20 _buyToken,
        uint128 _buySlippage,
        uint32 _batchDuration
    )
        public
        pure
        virtual
        override
        returns(bytes memory)
    {
        return abi.encodeWithSelector(
            this.action.selector,
            _origin,
            _sellToken,
            _sellAmount,
            _buyToken,
            _buySlippage,
            _batchDuration
        );
    }

    /// @notice Place order on Batch Exchange and request future withdraw for buy/sell token
    /// @param _sellToken Token to sell on Batch Exchange
    /// @param _sellAmount Amount to sell
    /// @param _buyToken Token to buy on Batch Exchange
    /// @param _buySlippage Slippage inlcuded for the buyAmount in order placement
    /// @param _batchDuration After how many batches funds should be
    function action(
        address _origin,
        IERC20 _sellToken,
        uint128 _sellAmount,
        IERC20 _buyToken,
        uint128 _buySlippage,
        uint32 _batchDuration
    )
        public
        virtual
        override
        delegatecallOnly("ActionPlaceOrderBatchExchangeWithSlippage.action")
    {
        uint128 expectedBuyAmount = getKyberBuyAmountWithSlippage(
            _sellToken,
            _buyToken,
            _sellAmount,
            _buySlippage
        );
        super.action(
            _origin, _sellToken, _sellAmount, _buyToken, expectedBuyAmount, _batchDuration
        );
    }

    function getKyberBuyAmountWithSlippage(
        IERC20 _sellToken,
        IERC20 _buyToken,
        uint128 _sellAmount,
        uint256 _slippage
    )
        view
        public
        returns(uint128 expectedBuyAmount128)
    {
        uint256 sellTokenDecimals = getDecimals(_sellToken);
        uint256 buyTokenDecimals = getDecimals(_buyToken);

        try kyber.getExpectedRate(address(_sellToken), address(_buyToken), _sellAmount)
            returns(uint256 expectedRate, uint256)
        {
            // Returned values in kyber are in 18 decimals
            // regardless of the destination token's decimals
            uint256 expectedBuyAmount256 = expectedRate
                // * sellAmount, as kyber returns the price for 1 unit
                .mul(_sellAmount)
                // * buy decimal tokens, to convert expectedRate * sellAmount to buyToken decimals
                .mul(10 ** buyTokenDecimals)
                // / sell token decimals to account for sell token decimals of _sellAmount
                .div(10 ** sellTokenDecimals)
                // / 10**18 to account for kyber always returning with 18 decimals
                .div(1e18);

            // return amount minus slippage. e.g. _slippage = 5 => 5% slippage
            expectedBuyAmount256
                = expectedBuyAmount256 - expectedBuyAmount256.mul(_slippage).div(100);
            expectedBuyAmount128 = uint128(expectedBuyAmount256);
            require(
                expectedBuyAmount128 == expectedBuyAmount256,
                "ActionPlaceOrderBatchExchangeWithSlippage.getKyberRate: uint conversion"
            );
        } catch {
            revert("ActionPlaceOrderBatchExchangeWithSlippage.getKyberRate:Error");
        }

    }

    function getDecimals(IERC20 _token)
        internal
        view
        returns(uint256)
    {
        (bool success, bytes memory data) = address(_token).staticcall{gas: 30000}(
            abi.encodeWithSignature("decimals()")
        );

        if (!success) {
            (success, data) = address(_token).staticcall{gas: 30000}(
                abi.encodeWithSignature("DECIMALS()")
            );
        }
        if (success) return abi.decode(data, (uint256));
        else revert("ActionPlaceOrderBatchExchangeWithSlippage.getDecimals:revert");
    }
}