pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import { IGelatoCore, Task, TaskReceipt } from "./interfaces/IGelatoCore.sol";
import { GelatoExecutors } from "./GelatoExecutors.sol";
import { GelatoDebug } from "../libraries/GelatoDebug.sol";
import { SafeMath } from "../external/SafeMath.sol";
import { IGelatoCondition } from "../gelato_conditions/IGelatoCondition.sol";
import { IGelatoAction } from "../gelato_actions/IGelatoAction.sol";
import { IGelatoProviderModule } from "../gelato_provider_modules/IGelatoProviderModule.sol";

/// @title GelatoCore
/// @author Luis Schliesske & Hilmar Orth
/// @notice Task: submission, validation, execution, charging and cancellation
/// @dev Find all NatSpecs inside IGelatoCore
contract GelatoCore is IGelatoCore, GelatoExecutors {

    using GelatoDebug for bytes;
    using SafeMath for uint256;

    // Setting State Vars for GelatoSysAdmin
    constructor(GelatoSysAdminInitialState memory _) public {
        gelatoGasPriceOracle = _.gelatoGasPriceOracle;
        oracleRequestData = _.oracleRequestData;
        gelatoMaxGas = _.gelatoMaxGas;
        internalGasRequirement = _.internalGasRequirement;
        minExecutorStake = _.minExecutorStake;
        executorSuccessShare = _.executorSuccessShare;
        sysAdminSuccessShare = _.sysAdminSuccessShare;
        totalSuccessShare = _.totalSuccessShare;
    }

    // ================  STATE VARIABLES ======================================
    // TaskReceiptIds
    uint256 public override currentTaskReceiptId;
    // taskReceipt.id => taskReceiptHash
    mapping(uint256 => bytes32) public override taskReceiptHash;

    // ================  SUBMIT ==============================================
    function canSubmitTask(address _userProxy, Task memory _task, uint256 _expiryDate)
        public
        view
        override
        returns(string memory)
    {
        // EXECUTOR CHECKS
        if (!isExecutorMinStaked(executorByProvider[_task.provider.addr]))
            return "GelatoCore.canSubmitTask: executorStake";

        // ExpiryDate
        if (_expiryDate != 0)
            if (_expiryDate < block.timestamp)
                return "GelatoCore.canSubmitTask: expiryDate";

        // Check Provider details
        string memory isProvided;
        if (_userProxy == _task.provider.addr)
            isProvided = providerModuleChecks(_userProxy, _task);
        else isProvided = isTaskProvided(_userProxy, _task);
        if (!isProvided.startsWithOk())
            return string(abi.encodePacked("GelatoCore.canSubmitTask.isProvided:", isProvided));

        // Success
        return OK;
    }

    function submitTask(Task memory _task, uint256 _expiryDate, uint256 _rounds) public override {
        // canSubmit Gate
        string memory canSubmitRes = canSubmitTask(msg.sender, _task, _expiryDate);
        require(canSubmitRes.startsWithOk(), canSubmitRes);

        // Generate new Task Receipt with single cycle
        Task[] memory singleCycle = new Task[](1);
        singleCycle[0] = _task;
        _storeTaskReceipt(msg.sender, 0, singleCycle, _expiryDate, _rounds);
    }

    function submitTaskCycle(Task[] memory _tasks, uint256 _expiryDate, uint256 _rounds) public override {
        // Check first task via canSubmit Gate
        require(_tasks.length > 1, "GelatoCore.submitTaskCycle:InvalidTaskLength");
        string memory canSubmitRes = canSubmitTask(msg.sender, _tasks[0],_expiryDate);
        require(canSubmitRes.startsWithOk(), canSubmitRes);

        _storeTaskReceipt(msg.sender, 0, _tasks, _expiryDate, _rounds);  // next == 1 at start
    }

    function _storeTaskReceipt(
        address _userProxy,
        uint256 _index,
        Task[] memory _cycle,
        uint256 _expiryDate,
        uint256 _rounds
    )
        private
    {
        // Increment TaskReceipt ID storage
        uint256 nextTaskReceiptId = currentTaskReceiptId + 1;
        currentTaskReceiptId = nextTaskReceiptId;

        // Generate new Task Receipt
        TaskReceipt memory taskReceipt = TaskReceipt({
            id: nextTaskReceiptId,
            userProxy: _userProxy, // Smart Contract Accounts ONLY
            index: _index,
            cycle: _cycle,
            rounds: _rounds,
            expiryDate: _expiryDate
        });

        // Hash TaskReceipt
        bytes32 hashedTaskReceipt = hashTaskReceipt(taskReceipt);

        // Store TaskReceipt Hash
        taskReceiptHash[taskReceipt.id] = hashedTaskReceipt;

        emit LogTaskSubmitted(taskReceipt.id, hashedTaskReceipt, taskReceipt);
    }

    // ================  CAN EXECUTE EXECUTOR API ============================
    function canExec(TaskReceipt memory _TR, uint256 _gelatoMaxGas, uint256 _gelatoGasPrice)
        public
        view
        override
        returns(string memory)
    {
        if (!isProviderLiquid(_TR.cycle[_TR.index].provider.addr, _gelatoMaxGas, _gelatoGasPrice))
            return "ProviderIlliquidity";

        if (_TR.userProxy != _TR.cycle[_TR.index].provider.addr) {
            string memory res = providerCanExec(_TR.userProxy, _TR.cycle[_TR.index], _gelatoGasPrice);
            if (!res.startsWithOk()) return res;
        }

        bytes32 hashedTaskReceipt = hashTaskReceipt(_TR);
        if (taskReceiptHash[_TR.id] != hashedTaskReceipt) return "InvalidTaskReceiptHash";

        if (_TR.expiryDate != 0 && _TR.expiryDate <= block.timestamp)
            return "TaskReceiptExpired";

        // Optional CHECK Condition for user proxies
        if (_TR.cycle[_TR.index].conditions.length != 0) {
            for (uint i; i < _TR.cycle[_TR.index].conditions.length; i++) {
                try _TR.cycle[_TR.index].conditions[i].inst.ok(_TR.cycle[_TR.index].conditions[i].data)
                    returns(string memory condition)
                {
                    if (!condition.startsWithOk())
                        return string(abi.encodePacked("ConditionNotOk:", condition));
                } catch Error(string memory error) {
                    return string(abi.encodePacked("ConditionReverted:", error));
                } catch {
                    return "ConditionReverted:undefined";
                }
            }
        }

        // Optional CHECK Action Terms
        for (uint i; i < _TR.cycle[_TR.index].actions.length; i++) {
            // Only check termsOk if specified, else continue
            if (!_TR.cycle[_TR.index].actions[i].termsOkCheck) continue;

            try IGelatoAction(_TR.cycle[_TR.index].actions[i].addr).termsOk(
                _TR.userProxy,
                _TR.cycle[_TR.index].actions[i].data
            )
                returns(string memory actionTermsOk)
            {
                if (!actionTermsOk.startsWithOk())
                    return string(abi.encodePacked("ActionTermsNotOk:", actionTermsOk));
            } catch Error(string memory error) {
                return string(abi.encodePacked("ActionReverted:", error));
            } catch {
                return "ActionRevertedNoMessage";
            }
        }

        // Check if we can submit the next task
        uint256 nextIndex = _getNextIndex(_TR);
        bool cannotSubmit = nextIndex == 0 && _TR.rounds == 1;
        if (!cannotSubmit) {
            string memory canResubmitSelf = canSubmitTask(_TR.userProxy, _TR.cycle[nextIndex], _TR.expiryDate);
            if (!canResubmitSelf.startsWithOk())
                return string(abi.encodePacked("CannotAutoResubmitSelf:", canResubmitSelf));
        }

        // Executor Validation
        if (msg.sender == address(this)) return OK;
        else if (msg.sender == executorByProvider[_TR.cycle[_TR.index].provider.addr])
            return OK;
        else return "InvalidExecutor";
    }

    // ================  EXECUTE EXECUTOR API ============================
    enum ExecutionResult { ExecSuccess, CanExecFailed, ExecRevert }
    enum ExecutorPay { Reward, Refund }

    // Execution Entry Point: tx.gasprice must be greater or equal to _getGelatoGasPrice()
    function exec(TaskReceipt memory _TR) public override {

        // Store startGas for gas-consumption based cost and payout calcs
        uint256 startGas = gasleft();

        // CHECKS: all further checks are done during this.executionWrapper.canExec()
        uint256 _internalGasRequirement = internalGasRequirement;
        require(startGas > _internalGasRequirement, "GelatoCore.exec: Insufficient gas sent");

        // memcopy of gelatoGasPrice, to avoid multiple storage reads
        uint256 gelatoGasPrice = _getGelatoGasPrice();
        require(
            tx.gasprice >= gelatoGasPrice,
            "GelatoCore.exec: tx.gasprice below gelatoGasPrice"
        );

        require(
            msg.sender == executorByProvider[_TR.cycle[_TR.index].provider.addr],
            "GelatoCore.exec: Invalid Executor"
        );

        // memcopy of gelatoMaxGas, to avoid multiple storage reads
        uint256 _gelatoMaxGas = gelatoMaxGas;

        ExecutionResult executionResult;
        string memory reason;

        try this.executionWrapper{gas: gasleft() - _internalGasRequirement}(
            _TR,
            _gelatoMaxGas,
            gelatoGasPrice
        )
            returns(ExecutionResult _executionResult, string memory _reason)
        {
            executionResult = _executionResult;
            reason = _reason;
        } catch Error(string memory error) {
            executionResult = ExecutionResult.ExecRevert;
            reason = error;
        } catch {
            // If any of the external calls in executionWrapper resulted in e.g. out of gas,
            // Executor is eligible for a Refund, but only if Executor sent gelatoMaxGas.
            executionResult = ExecutionResult.ExecRevert;
            reason = "GelatoCore.executionWrapper:undefined";
        }

        if (executionResult == ExecutionResult.ExecSuccess) {
            // END-1: SUCCESS => TaskReceipt Deletion & Reward
            delete taskReceiptHash[_TR.id];
            (uint256 executorSuccessFee, uint256 sysAdminSuccessFee) = _processProviderPayables(
                _TR.cycle[_TR.index].provider.addr,
                ExecutorPay.Reward,
                startGas,
                _gelatoMaxGas,
                gelatoGasPrice
            );
            emit LogExecSuccess(msg.sender, _TR.id, executorSuccessFee, sysAdminSuccessFee);

        } else if (executionResult == ExecutionResult.CanExecFailed) {
            // END-2: CanExecFailed => No TaskReceipt Deletion & No Refund
            emit LogCanExecFailed(msg.sender, _TR.id, reason);

        } else {
            // executionResult == ExecutionResult.ExecRevert
            // END-3.1: ExecReverted NO gelatoMaxGas => No TaskReceipt Deletion & No Refund
            if (startGas < _gelatoMaxGas) emit LogExecReverted(msg.sender, _TR.id, 0, reason);
            else {
                // END-3.2: ExecReverted BUT gelatoMaxGas was used
                //  => TaskReceipt Deletion & Refund
                delete taskReceiptHash[_TR.id];
                (uint256 executorRefund,) = _processProviderPayables(
                    _TR.cycle[_TR.index].provider.addr,
                    ExecutorPay.Refund,
                    startGas,
                    _gelatoMaxGas,
                     gelatoGasPrice
                );
                emit LogExecReverted(msg.sender, _TR.id, executorRefund, reason);
            }
        }
    }

    // Used by GelatoCore.exec(), to handle Out-Of-Gas from execution gracefully
    function executionWrapper(
        TaskReceipt memory taskReceipt,
        uint256 _gelatoMaxGas,
        uint256 _gelatoGasPrice
    )
        public
        returns(ExecutionResult, string memory)
    {
        require(msg.sender == address(this), "GelatoCore.executionWrapper:onlyGelatoCore");

        // canExec()
        string memory canExecRes = canExec(taskReceipt, _gelatoMaxGas, _gelatoGasPrice);
        if (!canExecRes.startsWithOk()) return (ExecutionResult.CanExecFailed, canExecRes);

        // Will revert if exec failed => will be caught in exec flow
        _exec(taskReceipt);

        // Execution Success: Executor REWARD
        return (ExecutionResult.ExecSuccess, "");
    }

    function _exec(TaskReceipt memory _TR) private {
        // We revert with an error msg in case of detected reverts
        string memory error;

        // INTERACTIONS
        // execPayload and proxyReturndataCheck values read from ProviderModule
        bytes memory execPayload;
        bool proxyReturndataCheck;

        try IGelatoProviderModule(_TR.cycle[_TR.index].provider.module).execPayload(
            _TR.cycle[_TR.index].actions
        )
            returns(bytes memory _execPayload, bool _proxyReturndataCheck)
        {
            execPayload = _execPayload;
            proxyReturndataCheck = _proxyReturndataCheck;
        } catch Error(string memory _error) {
            error = string(abi.encodePacked("GelatoCore._exec.execPayload:", _error));
        } catch {
            error = "GelatoCore._exec.execPayload:undefined";
        }

        // Execution via UserProxy
        bool success;
        bytes memory returndata;

        if (execPayload.length >= 4) (success, returndata) = _TR.userProxy.call(execPayload);
        else if (bytes(error).length == 0) error = "GelatoCore._exec.execPayload: invalid";

        // Check if actions reverts were caught by userProxy
        if (success && proxyReturndataCheck) {
            try _TR.cycle[_TR.index].provider.module.execRevertCheck(returndata)
                returns(bool _success)
            {
                success = _success;
            } catch Error(string memory _error) {
                error = string(abi.encodePacked("GelatoCore._exec.execRevertCheck:", _error));
            } catch {
                error = "GelatoCore._exec.execRevertCheck:undefined";
            }
        }

        // FAILURE: reverts, caught or uncaught in userProxy.call, were detected
        if (!success || bytes(error).length != 0) {
            // We revert all state from userProxy.call and catch revert in exec flow
            if (bytes(error).length == 0)
                returndata.revertWithErrorString("GelatoCore._exec:");
            revert(error);
        }

        // SUCCESS
        // Optional: Automated Cyclic Task Resubmission
        uint256 nextIndex = _getNextIndex(_TR);
        bool cannotSubmit = nextIndex == 0 && _TR.rounds == 1;
        if (!cannotSubmit) {
            uint256 nextRounds = _TR.rounds;
            // If the next index is 0 => we reached the end of this cycle
            // If _TR.rounds != 0  => We are not dealing with an infinite task
            if (nextIndex == 0 && _TR.rounds != 0) nextRounds = _TR.rounds - 1;
            _storeTaskReceipt(
                _TR.userProxy,
                nextIndex,
                _TR.cycle,
                _TR.expiryDate,
                nextRounds
            );
        }
    }

    function _processProviderPayables(
        address _provider,
        ExecutorPay _payType,
        uint256 _startGas,
        uint256 _gelatoMaxGas,
        uint256 _gelatoGasPrice
    )
        private
        returns(uint256 executorCompensation, uint256 sysAdminCompensation)
    {
        // Provider payable Gas Refund capped at gelatoMaxGas
        uint256 estExecTxGas = _startGas <= _gelatoMaxGas ? _startGas : _gelatoMaxGas;

        // ExecutionCost (- consecutive state writes + gas refund from deletion)
        uint256 estGasConsumed = (EXEC_TX_OVERHEAD + estExecTxGas).sub(
            gasleft(),
            "GelatoCore._processProviderPayables: estGasConsumed underflow"
        );

        if (_payType == ExecutorPay.Reward) {
            executorCompensation = executorSuccessFee(estGasConsumed, _gelatoGasPrice);
            sysAdminCompensation = sysAdminSuccessFee(estGasConsumed, _gelatoGasPrice);
            // ExecSuccess: Provider pays ExecutorSuccessFee and SysAdminSuccessFee
            providerFunds[_provider] = providerFunds[_provider].sub(
                executorCompensation.add(sysAdminCompensation),
                "GelatoCore._processProviderPayables: providerFunds underflow"
            );
            executorStake[msg.sender] += executorCompensation;
            sysAdminFunds += sysAdminCompensation;
        } else {
            // ExecFailure: Provider REFUNDS estimated costs to executor
            executorCompensation = estGasConsumed.mul(_gelatoGasPrice);
            providerFunds[_provider] = providerFunds[_provider].sub(
                executorCompensation,
                "GelatoCore._processProviderPayables: providerFunds underflow"
            );
            executorStake[msg.sender] += executorCompensation;
        }
    }

    // ================  CANCEL USER / EXECUTOR API ============================
    function cancelTask(TaskReceipt memory _TR) public override {
        // Checks
        require(
            msg.sender == _TR.userProxy || msg.sender == _TR.cycle[_TR.index].provider.addr,
            "GelatoCore.cancelTask: sender"
        );
        // Effects
        bytes32 hashedTaskReceipt = hashTaskReceipt(_TR);
        require(
            hashedTaskReceipt == taskReceiptHash[_TR.id],
            "GelatoCore.cancelTask: invalid taskReceiptHash"
        );
        delete taskReceiptHash[_TR.id];
        emit LogTaskCancelled(_TR.id, msg.sender);
    }

    function multiCancelTasks(TaskReceipt[] memory _taskReceipts) public override {
        for (uint i; i < _taskReceipts.length; i++) cancelTask(_taskReceipts[i]);
    }

    // Helpers
    function hashTaskReceipt(TaskReceipt memory _TR) public pure override returns(bytes32) {
        return keccak256(abi.encode(_TR));
    }

    function _getNextIndex(TaskReceipt memory _TR) private pure returns(uint256) {
        return _TR.index == _TR.cycle.length - 1 ? 0 : _TR.index + 1;
    }
}
