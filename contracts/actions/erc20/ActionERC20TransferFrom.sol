pragma solidity ^0.6.0;

import "../GelatoActionsStandard.sol";
import "../../external/IERC20.sol";
// import "../../external/SafeERC20.sol";
import "../../dapp_interfaces/kyber/IKyber.sol";
import "../../external/SafeMath.sol";
import "../../external/Address.sol";

contract ActionERC20TransferFrom is GelatoActionsStandard {
    // using SafeERC20 for IERC20; <- internal library methods vs. try/catch
    using SafeMath for uint256;
    using Address for address;

    // actionSelector public state variable np due to this.actionSelector constant issue
    function actionSelector() external pure override returns(bytes4) {
        return this.action.selector;
    }
    uint256 public constant override actionGas = 80000;

    function action(
        // Standard Action Params
        address _user,
        address _userProxy,
        // Specific Action Params
        address _src,
        uint256 _srcAmt,
        address _beneficiary
    )
        external
        virtual
    {
        require(
            _isUserOwnerOfUserProxy(_user, _userProxy),
            "ActionERC20TransferFrom: NotOkUserProxyOwner"
        );
        require(address(this) == _userProxy, "ActionERC20TransferFrom: ErrorUserProxy");
        IERC20 srcERC20 = IERC20(_src);
        try srcERC20.transferFrom(_user, _beneficiary, _srcAmt) {} catch {
            revert("ActionERC20TransferFrom: ErrorTransferFromUser");
        }
    }

    // ======= ACTION CONDITIONS CHECK =========
    // Overriding and extending GelatoActionsStandard's function (optional)
    function actionConditionsCheck(bytes calldata _actionPayloadWithSelector)
        external
        view
        override
        virtual
        returns(string memory)  // actionCondition
    {
        return _actionConditionsCheck(_actionPayloadWithSelector);
    }

    function _actionConditionsCheck(bytes memory _actionPayloadWithSelector)
        internal
        view
        virtual
        returns(string memory)  // actionCondition
    {
        (, bytes memory payload) = SplitFunctionSelector.split(
            _actionPayloadWithSelector
        );

        (address _user, address _userProxy, address _src, uint256 _srcAmt,) = abi.decode(
            payload,
            (address, address, address, uint256, address)
        );

        if (!_isUserOwnerOfUserProxy(_user, _userProxy))
            return "ActionERC20Transfer: NotOkUserProxyOwner";

        if (!_src.isContract()) return "ActionERC20TransferFrom: NotOkSrcAddress";

        IERC20 srcERC20 = IERC20(_src);
        try srcERC20.balanceOf(_user) returns(uint256 srcBalance) {
            if (srcBalance < _srcAmt) return "ActionERC20TransferFrom: NotOkUserBalance";
        } catch {
            return "ActionERC20TransferFrom: ErrorBalanceOf";
        }
        try srcERC20.allowance(_user, _userProxy) returns(uint256 userProxyAllowance) {
            if (userProxyAllowance < _srcAmt)
                return "ActionERC20TransferFrom: NotOkUserProxyAllowance";
        } catch {
            return "ActionERC20TransferFrom: ErrorAllowance";
        }

        // STANDARD return string to signal actionConditions Ok
        return "ok";
    }

    // ============ API for FrontEnds ===========
    function getUsersSourceTokenBalance(
        // Standard Action Params
        address _user,
        address _userProxy,
        // Specific Action Params
        address _src,
        uint256,
        address
    )
        external
        view
        virtual
        returns(uint256)
    {
        _userProxy;  // silence warning
        IERC20 srcERC20 = IERC20(_src);
        try srcERC20.balanceOf(_user) returns(uint256 userSrcBalance) {
            return userSrcBalance;
        } catch {
            revert("Error: ActionERC20TransferFrom.getUsersSourceTokenBalance: balanceOf");
        }
    }
}