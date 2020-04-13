pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import { IGelatoProviderModule } from "../../interfaces/IGelatoProviderModule.sol";
import { IProviderModuleGelatoUserProxy } from "./IProviderModuleGelatoUserProxy.sol";
import { Ownable } from "../../../external/Ownable.sol";
import { Action, ExecClaim } from "../../interfaces/IGelatoCore.sol";
import {
    IGelatoUserProxy
} from "../../../user_proxies/gelato_user_proxy/IGelatoUserProxy.sol";

contract ProviderModuleGelatoUserProxy is
    IGelatoProviderModule,
    IProviderModuleGelatoUserProxy,
    Ownable
{
    mapping(bytes32 => bool) public override isProxyExtcodehashProvided;

    constructor(bytes32[] memory hashes) public { provideProxyExtcodehashes(hashes); }

    // ================= GELATO PROVIDER MODULE STANDARD ================
    // @dev since we check extcodehash prior to execution, we forego the execution option
    //  where the userProxy is deployed at execution time.
    function isProvided(ExecClaim calldata _ec)
        external
        view
        override
        returns(string memory)
    {
        address userProxy = _ec.userProxy;
        bytes32 codehash;
        assembly { codehash := extcodehash(userProxy) }
        if (!isProxyExtcodehashProvided[codehash])
            return "ProviderModuleGelatoUserProxy.isProvided:InvalidExtcodehash";

        return "Ok";
    }

    function execPayload(Action[] calldata _actions)
        external
        pure
        override
        returns(bytes memory)
    {
        if (_actions.length > 1) {
            return abi.encodeWithSelector(
                IGelatoUserProxy.multiDelegatecallActions.selector,
                _actions
            );
        } else if (_actions.length == 1) {
            return abi.encodeWithSelector(
                IGelatoUserProxy.delegatecallAction.selector,
                _actions[0]
            );
        }
    }

    // GnosisSafeProxy
    function provideProxyExtcodehashes(bytes32[] memory _hashes) public override onlyOwner {
        for (uint i; i < _hashes.length; i++) {
            require(
                !isProxyExtcodehashProvided[_hashes[i]],
                "ProviderModuleGelatoUserProxy.provideProxyExtcodehashes: redundant"
            );
            isProxyExtcodehashProvided[_hashes[i]] = true;
            emit LogProvideProxyExtcodehash(_hashes[i]);
        }
    }

    function unprovideProxyExtcodehashes(bytes32[] memory _hashes) public override onlyOwner {
        for (uint i; i < _hashes.length; i++) {
            require(
                isProxyExtcodehashProvided[_hashes[i]],
                "ProviderModuleGelatoUserProxy.unprovideProxyExtcodehashes: redundant"
            );
            delete isProxyExtcodehashProvided[_hashes[i]];
            emit LogUnprovideProxyExtcodehash(_hashes[i]);
        }
    }
}