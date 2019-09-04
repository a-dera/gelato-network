pragma solidity >=0.4.21 <0.6.0;

//  Imports:
import '@gnosis.pm/dx-contracts/contracts/DutchExchange.sol';
import '../../GelatoCore.sol';
import '../../base/Counters.sol';
import '../../base/ERC20.sol';
import '../../base/IcedOut.sol';
import '../../base/Ownable.sol';
import '../../base/SafeMath.sol';


// Gelato IcedOut-compliant DutchX Interface for splitting sell orders and for automated withdrawals
contract GelatoDutchX is IcedOut, SafeTransfer {
    // parent => Ownable => indirect use through IcedOut
    // Libraries
    // using SafeMath for uint256; => indirect use through IcedOut
    using Counters for Counters.Counter;

    Counters.Counter private orderIds;

    // One OrderState has many SellOrder
    struct OrderState {
        // address sellToken; // token to sell
        // address buyToken; // token to buy
        bool lastAuctionWasWaiting;  // default: false
        uint256 lastAuctionIndex;  // default: 0
        // uint256 prepaymentPerSellOrder; // maxGas * gelatoGasPrice
    }


    // **************************** Events ******************************
    event LogNewOrderCreated(uint256 indexed orderStateId, address indexed seller);
    event LogFeeNumDen(uint256 num, uint256 den);
    event LogActualSellAmount(uint256 indexed executionClaimId,
                              uint256 indexed orderId,
                              uint256 subOrderAmount,
                              uint256 actualSellAmount,
                              uint256 dutchXFee
    );
    event LogOrderCancelled(uint256 indexed executionClaimId,
                            uint256 indexed orderID,
                            address indexed seller
    );
    event LogWithdrawComplete(uint256 indexed executionClaimId,
                              uint256 indexed orderId,
                              address indexed seller,
                              address buyToken,
                              uint256 withdrawAmount
    );
    event LogOrderCompletedAndDeleted(uint256 indexed orderId);
    event LogWithdrawAmount(uint256 num, uint256 den, uint256 withdrawAmount);
    event LogGas(uint256 gas1, uint256 gas2);
    // **************************** Events END ******************************


    // **************************** State Variables ******************************

    // Interfaces to other contracts that are set during construction.
    // GelatoCore public gelatoCore;
    DutchExchange public dutchExchange;

    // One orderState struct can have many sellOrder structs as children

    // OrderId => parent orderState struct
    // mapping(uint256 => OrderState) public orderStates;

    // gelatoCore executionId => individual sellOrder struct
    // Note 2 executionIds will map to the same sellOrder struct (execDepositAndSell and withdraw)
    // mapping(uint256 => SellOrder) public sellOrders;

    // // Map execWithdraw claim to respective execDepositAndSellClaim
    // mapping(uint256 => uint256) public sellOrderLink;

    // withdraw execution claim => depositAndSell exeuctionClaim => sellOrder
    // mapping(uint256 => mapping(uint256 => SellOrder)) public sellOrders;
    mapping(uint256 => OrderState) public orderStates;

    // Constants that are set during contract construction and updateable via setters
    uint256 public auctionStartWaitingForFunding;

    string constant execDepositAndSellString = "execDepositAndSell(uint256,address,address,uint256,uint256,uint256)";
    string constant execWithdrawString = "execWithdraw(uint256,address,address,uint256,uint256,uint256)";

    // **************************** State Variables END ******************************

    /* constructor():
        * constructs Ownable base and sets msg.sender as owner.
        * connects the contract interfaces to deployed instances thereof.
        * sets the state variable constants
    */
    constructor(address payable _GelatoCore, address _DutchExchange)
        // Initialize gelatoCore address & maxGas in IcedOut parent
        IcedOut(_GelatoCore, 500000) // maxGas 277317 for depsositAndSell
        public
    {
        // gelatoCore = GelatoCore(_GelatoCore);
        dutchExchange = DutchExchange(_DutchExchange);
        auctionStartWaitingForFunding = 1;
    }


    // **************************** State Variable Setters ******************************
    function setAuctionStartWaitingForFunding(uint256 _auctionStartWaitingForFunding)
        onlyOwner
        external
    {
        auctionStartWaitingForFunding = _auctionStartWaitingForFunding;
    }
    // **************************** State Variable Setters END ******************************

    // **************************** timeSellOrders() ******************************
    function timeSellOrders(address _sellToken,
                            address _buyToken,
                            uint256 _totalSellVolume,
                            uint256 _numSellOrders,
                            uint256 _sellOrderAmount,
                            uint256 _executionTime,
                            uint256 _intervalSpan
    )
        public
        payable
        returns (bool)

    {
        // Step1: Zero value preventions
        require(_sellToken != address(0), "GelatoCore.mintExecutionClaim: _sellToken: No zero addresses allowed");
        require(_buyToken != address(0), "GelatoCore.mintExecutionClaim: _buyToken: No zero addresses allowed");
        require(_sellOrderAmount != 0, "GelatoCore.mintExecutionClaim: _sellOrderAmount cannot be 0");
        require(_totalSellVolume != 0, "splitSellOrder: totalSellVolume cannot be 0");
        require(_numSellOrders != 0, "splitSellOrder: numSubOrders cannot be 0");

        // Step2: Valid execution Time check
        // Check that executionTime is in the future (10 minute buffer given)
        require(_executionTime.add(10 minutes) >= now, "GelatoCore.mintExecutionClaim: Failed test: Execution time must be in the future");
        // Time between different selOrders needs to be at least 6 hours
        require(_intervalSpan >= 6 hours,
            "splitSellOrder: _intervalSpan not at/above minimum of 6 hours"
        );

        // Step3: Invariant Requirements
        // Require that user transfers the correct prepayment amount. Charge 2x execute + Withdraw
        uint256 prepaymentPerSellOrder = calcGelatoPrepayment();
        require(msg.value == prepaymentPerSellOrder.mul(_numSellOrders),  // calc for msg.sender==dappInterface
            "User ETH prepayment transfer is incorrect"
        );
        // Only tokens that are tradeable on the Dutch Exchange can be posted
        require(dutchExchange.getAuctionIndex(_sellToken, _buyToken) != 0, "The selected tokens are not traded on the Dutch Exchange");
        // Total Sell Volume must equal individual sellOrderAmount * number of sellOrders
        require(_totalSellVolume == _numSellOrders.mul(_sellOrderAmount),
            "splitSellOrder: _totalSellVolume != _numSellOrders * _sellOrderAmount"
        );

        // Step4: Transfer the totalSellVolume from msg.sender(seller) to this contract
        // this is hardcoded into SafeTransfer.sol
        require(safeTransfer(_sellToken, address(this), _totalSellVolume, true),
            "splitSellOrder: The transfer of sellTokens from msg.sender to Gelato Interface must succeed"
        );

        // Step5: Instantiate new dutchExchange-specific sell order state
        OrderState memory orderState = OrderState(
            // _sellToken,
            // _buyToken,
            false,  // default: lastAuctionWasWaiting
            0  // default: lastAuctionIndex
            // prepaymentPerSellOrder
        );

        // // Step6: fetch new OrderStateId and store orderState in orderState mapping
        // // Increment the current OrderId
        // Counters.increment(orderIds);
        // // Get a new, unique OrderId for the newly created Sell Order
        // uint256 orderStateId = orderIds.current();
        // // Update GelatoDutchX state variables
        // orderStates[orderStateId] = orderState;

        // Step7: Create all sellOrders
        for (uint256 i = 0; i < _numSellOrders; i++) {
            // SellOrder memory sellOrder = SellOrder(
            //     orderStateId,
            //     _executionTime.add(_intervalSpan.mul(i)),
            //     _sellOrderAmount,
            //     false // not withdrawn yet
            // );

            uint256 executionTime = _executionTime.add(_intervalSpan.mul(i));

            uint256 nextExecutionClaimId = getNextExecutionClaimId();

            // Payload: (funcSelector, uint256 executionClaimId, address sellToken, address buyToken, uint256 amount, uint256 executionTime, uint256 prepaymentPerSellOrder)
            bytes memory payload = abi.encodeWithSignature(execDepositAndSellString, nextExecutionClaimId, _sellToken, _buyToken, _sellOrderAmount, executionTime, prepaymentPerSellOrder);

            // For each sellOrder, mint one claim that call the execDepositAndSell function
            mintClaim(msg.sender, payload);

            // For each sellOrder, mint one claim that call the execWithdraw function
            // (uint256 nextExecutionClaimIdPlusOne, ) = mintClaim("execWithdraw(uint256)", msg.sender);

            // Map first claims to the Sell Order and second claims to the first claim => BONDED Claims
            // withdraw execution claim => depositAndSell exeuctionClaim => sellOrder
            orderStates[nextExecutionClaimId] = orderState;

            // withdraw execution claim => depositAndSell exeuctionClaim => sellOrder
            //  *** GELATO CORE PROTOCOL INTERACTION END ***
        }


        // Step8: Emit New Sell Order to find its suborder constituent claims on the Core
        return true;
    }
    // **************************** timeSellOrders() END ******************************

    // acceptExecutionRequest func that checks whether function is executable or not
    function acceptExecutionRequest(bytes calldata _payload)
        external
        view
        returns (uint256)
    {
        // Check that payload length is greater 4
        require(_payload.length > 4, "Payload must be larger than 4 bytes");

        // Make a memory copy of the payload (calldata)
        bytes memory memPayload = _payload;

        bytes4 funcSelector;
        (memPayload, funcSelector) = decodeWithFunctionSignature(memPayload);

        // Check which function selector was passed
        if (funcSelector == bytes4(keccak256(bytes(execDepositAndSellString))))
        {
            // If executable, should return 0
            return execDepositAndSellCheck(memPayload);

        }
        else if (funcSelector == bytes4(keccak256(bytes(execWithdrawString))))
        {
            // If executable, should return 0
            return execWithdrawCheck(memPayload);

        }
        else {
            // Error in funcSelector
            return 1;
        }

    }

    // Check if execDepositAndSell is executable
    function execDepositAndSellCheck(bytes memory _memPayload)
        internal
        view
        returns (uint256)
    {
        // Decode payload
        (uint256 executionClaimId, address sellToken, address buyToken, uint256 amount, uint256 executionTime, uint256 prepaymentPerSellOrder) = abi.decode(_memPayload, (uint256, address, address, uint256, uint256, uint256));

        // Init state variables
        // SellOrder memory sellOrder = sellOrders[_executionClaimId + 1][_executionClaimId];
        // uint256 amount = sellOrder.amount;

        // Check the condition: Execution Time
        // checkTimeCondition(sellOrder.executionTime);
        checkTimeCondition(executionTime);

        // Fetch OrderState
        OrderState memory orderState = orderStates[executionClaimId];
        // uint256 orderStateId = sellOrder.orderStateId;
        // OrderState memory orderState = orderStates[orderStateId];

        // address sellToken = orderState.sellToken;
        // address buyToken = orderState.buyToken;
        // uint256 lastAuctionIndex = orderState.lastAuctionIndex;

        uint256 lastAuctionIndex = orderState.lastAuctionIndex;
        bool lastAuctionWasWaiting = orderState.lastAuctionWasWaiting;  // default: false

        uint256 newAuctionIndex = dutchExchange.getAuctionIndex(sellToken, buyToken);
        uint256 auctionStartTime = dutchExchange.getAuctionStart(sellToken, buyToken);

        // Waiting Period variables needed to prevent double participation in DutchX auctions
        bool newAuctionIsWaiting;
        // Check if we are in a Waiting period or auction running period
        if (auctionStartTime > now || auctionStartTime == auctionStartWaitingForFunding)
        {
            newAuctionIsWaiting = true;
        }
        else if (auctionStartTime < now)
        {
            newAuctionIsWaiting = false;
        }

        // Check if interface has enough funds to sell on the Dutch Exchange
        require(
            ERC20(sellToken).balanceOf(address(this)) >= amount,
            "GelatoInterface.execute: ERC20(sellToken).balanceOf(address(this)) !>= subOrderSize"
        );

        if (newAuctionIndex == lastAuctionIndex)
        {
            require(lastAuctionWasWaiting && !newAuctionIsWaiting,
            "newAuctionindex == lastAuctionIndex, but lastAuctionWasWaiting && !newAuctionIsWaiting == false");
            return 0;
        }
        else if (newAuctionIndex == lastAuctionIndex.add(1))
        {
            require(lastAuctionWasWaiting && newAuctionIsWaiting || lastAuctionWasWaiting && !newAuctionIsWaiting,
            "newAuctionIndex == lastAuctionIndex.add(1), but lastAuctionWasWaiting && newAuctionIsWaiting || lastAuctionWasWaiting && !newAuctionIsWaiting == false");
            return 0;
        }
        else if (newAuctionIndex >= lastAuctionIndex.add(2))
        {
            return 0;
        }
        else
        {
            // Claim not executable
            revert("Case5: Fatal Error: Case5 unforeseen");
        }
    }

    // Test if execWithdraw is executable
    function execWithdrawCheck(bytes memory _memPayload)
        internal
        view
        returns (uint256)
    {
        // Decode payload
        (uint256 executionClaimId, address sellToken, address buyToken, uint256 amount, uint256 prepaymentPerSellOrder, uint256 lastAuctionIndex) = abi.decode(_memPayload, (uint256, address, address, uint256, uint256, uint256));

        // Check if auction in DutchX closed
        uint256 num;
        uint256 den;
        (num, den) = dutchExchange.closingPrices(sellToken,
                                                buyToken,
                                                lastAuctionIndex
        );

        // Check if the last auction the seller participated in has cleared
        // DEV Test: Are there any other possibilities for den being 0 other than when the auction has not yet cleared?
        require(den != 0,
            "den != 0, Last auction did not clear thus far, you have to wait"
        );

        // // All checks passed
        return 0;
    }


    // ****************************  execDepositAndSell(executionClaimId) *********************************
    /**
     * DEV: Called by the execute func in GelatoCore.sol
     * Aim: Post sellOrder on the DutchExchange via depositAndSell()
     */
    function execDepositAndSell(uint256 _executionClaimId, address _sellToken, address _buyToken, uint256 _amount, uint256 _executionTime, uint256 _prepaymentPerSellOrder)
        external
        returns (bool)
    {
        // Step1: Checks for execution safety
        // Make sure that gelatoCore is the only allowed caller to this function.
        // Executors will call this execute function via the Core's execute function.
        require(msg.sender == address(gelatoCore),
            "GelatoInterface.execute: msg.sender != gelatoCore instance address"
        );

        // Step2: Create storage pointer for the individual sellOrder and the parent orderState
        // Fetch SellOrder
        // SellOrder storage sellOrder = sellOrders[_executionClaimId + 1][_executionClaimId];

        // Fetch OrderState
        // uint256 orderStateId = sellOrder.orderStateId;
        // OrderState storage orderState = orderStates[orderStateId];

        // Fetch owner of execution claim
        address tokenOwner = gelatoCore.ownerOf(_executionClaimId);
        OrderState storage orderState = orderStates[_executionClaimId];

        // Step4: initialise multi-use variables
        // ********************** Load variables from storage and initialise them **********************
        // address sellToken = orderState.sellToken;
        // address buyToken = orderState.buyToken;
        // uint256 amount = sellOrder.amount;
        // ********************** Load variables from storage and initialise them END **********************

        // Step5: Fetch auction specific data from Dutch Exchange
        // ********************** Fetch data from dutchExchange **********************
        uint256 newAuctionIndex = dutchExchange.getAuctionIndex(_sellToken, _buyToken);
        uint256 auctionStartTime = dutchExchange.getAuctionStart(_sellToken, _buyToken);
        // ********************** Fetch data from dutchExchange END **********************

        // Step7: Set the auction specific orderState variables
        // Waiting Period variables needed to prevent double participation in DutchX auctions
        bool newAuctionIsWaiting;
        // Check if we are in a Waiting period or auction running period
        if (auctionStartTime > now || auctionStartTime == auctionStartWaitingForFunding)
        {
            newAuctionIsWaiting = true;
        }
        else if (auctionStartTime < now)
        {
            newAuctionIsWaiting = false;
        }

        // ### EFFECTS ###
        // Update Order State
        orderState.lastAuctionWasWaiting = newAuctionIsWaiting;
        orderState.lastAuctionIndex = newAuctionIndex;

        uint256 actualSellAmount;
        {
            uint256 dutchXFee;
            // Update sellOrder.amount so when an executor calls execWithdraw, the seller receives withdraws the correct amount given sellAmountMinusFee
            (actualSellAmount, dutchXFee) = _calcActualSellAmount(_amount);

            emit LogActualSellAmount(
                                    _executionClaimId,
                                    _executionClaimId,
                                    _amount,
                                    actualSellAmount,
                                    dutchXFee
            );
            // ### EFFECTS END ###

            // INTERACTION: sell on dutchExchange
            _depositAndSell(_sellToken, _buyToken, _amount);
            // INTERACTION: END
        }

        // Mint new token
        {
            // Fetch next executionClaimId
            uint256 nextExecutionClaimId = getNextExecutionClaimId();

            // Payload: (funcSelector, uint256 executionClaimId, address sellToken, address buyToken, uint256 amount, uint256 prepaymentPerSellOrder, uint256 lastAuctionIndex)
            bytes memory payload = abi.encodeWithSignature(execWithdrawString, nextExecutionClaimId, _sellToken, _buyToken, actualSellAmount, _prepaymentPerSellOrder, newAuctionIndex);

            // Mint new withdraw token
            mintClaim(tokenOwner, payload);

        }

        // ********************** Step7: Execution Logic END **********************

        // Step8:  Check if interface still has sufficient balance on core. If not, add balance. If yes, skip.
        automaticTopUp();

        return true;
    }
    // **************************** IcedOut execute(executionClaimId) END *********************************

    // Withdraw function executor will call
    function execWithdraw(uint256 _executionClaimId, address _sellToken, address _buyToken, uint256 _amount, uint256 _prepaymentPerSellOrder, uint256 lastAuctionIndex)
        public
    {
        // Step1: Checks for execution safety
        // Make sure that gelatoCore is the only allowed caller to this function.
        // Executors will call this execute function via the Core's execute function.
        require(msg.sender == address(gelatoCore),
            "GelatoInterface.execute: msg.sender != gelatoCore instance address"
        );

        // Fetch owner of execution claim
        address seller = gelatoCore.ownerOf(_executionClaimId);

        // Calculate withdraw amount
        uint256 withdrawAmount = _withdraw(seller,
                                           _sellToken,
                                           _buyToken,
                                           lastAuctionIndex,
                                           _amount //Actual amount posted
        );

        // Event emission
        emit LogWithdrawComplete(_executionClaimId,
                                 _executionClaimId,
                                 seller,
                                 _buyToken,
                                 withdrawAmount
        );
    }

    // **************************** Helper functions *********************************
    // Calculate sub order size accounting for current dutchExchange liquidity contribution fee.
    function _calcActualSellAmount(uint256 _subOrderSize)
        public
        returns(uint256 actualSellAmount, uint256 dutchXFee)
    {
        // Get current fee ratio of Gelato contract
        uint256 num;
        uint256 den;
        // Returns e.g. num = 1, den = 500 for 0.2% fee
        (num, den) = dutchExchange.getFeeRatio(address(this));

        emit LogFeeNumDen(num, den);

        // Calc fee amount
        dutchXFee = _subOrderSize.mul(num).div(den);

        // Calc actual Sell Amount
        actualSellAmount = _subOrderSize.sub(dutchXFee);
    }

    // Deposit and sell on the dutchExchange
    function _depositAndSell(address _sellToken,
                             address _buyToken,
                             uint256 _sellAmount
    )
        private
    {
        // Approve DutchX to transfer the funds from gelatoInterface
        ERC20(_sellToken).approve(address(dutchExchange), _sellAmount);

        // DEV deposit and sell on the dutchExchange
        dutchExchange.depositAndSell(_sellToken, _buyToken, _sellAmount);
    }

    // Internal fn that withdraws funds from dutchExchange to the sellers account
    function _withdraw(address _seller,
                       address _sellToken,
                       address _buyToken,
                       uint256 _lastAuctionIndex,
                       uint256 _sellAmountAfterFee
    )
        public
        returns(uint256 withdrawAmount)
    {
        // Calc how much the amount of buy_tokens received in the previously participated auction
        withdrawAmount = _calcWithdrawAmount(_sellToken,
                                             _buyToken,
                                             _lastAuctionIndex,
                                             _sellAmountAfterFee
        );

        // Withdraw funds from dutchExchange to Gelato
        // DEV uses memory value lastAuctionIndex in case execute func calls it as we already incremented storage value
        dutchExchange.claimAndWithdraw(_sellToken,
                                       _buyToken,
                                       address(this),
                                       _lastAuctionIndex,
                                       withdrawAmount
        );

        // Transfer Tokens from Gelato to Seller
        safeTransfer(_buyToken, _seller, withdrawAmount, false);
    }

    // DEV Calculates amount withdrawable from past, cleared auction
    function _calcWithdrawAmount(address _sellToken,
                                 address _buyToken,
                                 uint256 _lastAuctionIndex,
                                 uint256 _sellAmountAfterFee
    )
        public
        returns(uint256 withdrawAmount)
    {
        // Fetch numerator and denominator from dutchExchange
        uint256 num;
        uint256 den;

        // FETCH PRICE OF CLEARED ORDER WITH INDEX lastAuctionIndex
        // num: buyVolumeOpp || den: sellVolumeOpp
        // Ex: num = 1000, den = 10 => 1WETH === 100RDN
        (num, den) = dutchExchange.closingPrices(_sellToken,
                                                 _buyToken,
                                                 _lastAuctionIndex
        );

        // Check if the last auction the seller participated in has cleared
        // DEV Check line 442 in dutchExchange contract
        // DEV Test: Are there any other possibilities for den being 0 other than when the auction has not yet cleared?
        require(den != 0,
            "withdrawManually: den != 0, Last auction did not clear thus far, you have to wait"
        );

        emit LogWithdrawAmount(num, den, _sellAmountAfterFee.mul(num).div(den));

        // Callculate withdraw amount
        withdrawAmount = _sellAmountAfterFee.mul(num).div(den);

    }
    // **************************** Helper functions END *********************************



    // **************************** Extra functions *********************************
    // Allows sellers to cancel their deployed orders
    // @🐮 create cancel helper on IcedOut.sol

    function cancelOrder(uint256 _executionClaimId)
        public
        returns(bool)
    {
        // Fetch calldata from gelato core and decode
        bytes memory payload = gelatoCore.getClaimPayload(_executionClaimId);

        (bytes memory memPayload, bytes4 funcSelector) = decodeWithFunctionSignature(payload);

        // #### CHECKS ####
        // @DEV check that we are dealing with a execDepositAndSell claim
        require(funcSelector == bytes4(keccak256(bytes(execDepositAndSellString))), "Only claims that have not been sold yet can be cancelled");

        (uint256 executionClaimId, address sellToken, , uint256 amount, , uint256 prepaymentPerSellOrder) = abi.decode(memPayload, (uint256, address, address, uint256, uint256, uint256));

        // address seller = gelatoCore.ownerOf(_executionClaimId);
        address tokenOwner = gelatoCore.ownerOf(_executionClaimId);

        // Only Execution Claim Owner can cancel
        //@DEV We could add that the interface owner can also cancel an execution claim to avoid having oustanding claims that might never get executed. Discuss
        require(msg.sender == tokenOwner, "Only the executionClaim Owner can cancel the execution");

        // // #### CHECKS END ####

        // CHECKS: msg.sender == executionClaimOwner is checked by Core

        // ****** EFFECTS ******
        // Emit event before deletion/burning of relevant variables
        emit LogOrderCancelled(executionClaimId, executionClaimId, tokenOwner);

        // Cancel both execution Claims on core
        // ** Gelato Core interactions **
        gelatoCore.cancelExecutionClaim(executionClaimId);
        // ** Gelato Core interactions END **

        // ****** EFFECTS END ******

        // ****** INTERACTIONS ******
        // transfer sellAmount back from this contracts ERC20 balance to seller
        // Refund user the given prepayment amount!!!
        msg.sender.transfer(prepaymentPerSellOrder);

        // Transfer ERC20 Tokens back to seller
        safeTransfer(sellToken, msg.sender, amount, false);

        // // ****** INTERACTIONS END ******

        // Success
        return true;
    }

    // Allows manual withdrawals on behalf of a seller from any calling address
    // This is allowed also on the GelatoDutchX Automated Withdrawal Interface
    //  because all remaining claims are still executable (do not throw revert as a result)
    //  since they still do postSellOrder. Actually they could now even be a bit cheaper
    //   to execute for the executor, as no withdrawal control flow is entered any more.
    // withdrawManually only works up until the last withdrawal because the last withdrawal is its
    //  own ExecutionClaim on the Core, and a manual withdrawal thereof would result in unwanted complexity.
    // @DEV: Gas Limit Change => Hardcode
    function withdrawManually(uint256 _executionClaimId)
        external
        returns(bool)
    {
        // Fetch owner of execution claim
        address tokenOwner = gelatoCore.ownerOf(_executionClaimId);

         // Fetch calldata from gelato core and decode
        bytes memory payload = gelatoCore.getClaimPayload(_executionClaimId);

        (bytes memory memPayload, bytes4 funcSelector) = decodeWithFunctionSignature(payload);

        // #### CHECKS ####
        // @DEV check that we are dealing with a execWithdraw claim
        require(funcSelector == bytes4(keccak256(bytes(execWithdrawString))), "Only claims that have not been sold yet can be cancelled");

        // Decode payload
        (uint256 executionClaimId, address sellToken, address buyToken, uint256 amount, uint256 prepaymentPerSellOrder, uint256 lastAuctionIndex) = abi.decode(memPayload, (uint256, address, address, uint256, uint256, uint256));

        // ******* CHECKS *******
        // If amount == 0, struct has already been deleted
        require(amount != 0, "Amount for manual withdraw cannot be zero");
        // Only Execution Claim Owner can withdraw manually
        require(msg.sender == tokenOwner, "Only the executionClaim Owner can cancel the execution");


        // Fetch price of last participated in and cleared auction using lastAuctionIndex
        uint256 num;
        uint256 den;
        (num, den) = dutchExchange.closingPrices(sellToken, buyToken, lastAuctionIndex);

        // Require that the last auction the seller participated in has cleared
        require(den != 0,
            "withdrawManually: den != 0, Last auction did not clear thus far, you have to wait"
        );
        // ******* CHECKS END *******

        // ******* INTERACTIONS *******

        // Cancel execution claim on core
        gelatoCore.cancelExecutionClaim(_executionClaimId);

        // Initiate withdraw
        _withdraw(tokenOwner,  // seller
                  sellToken,
                  buyToken,
                  lastAuctionIndex,
                  amount
        );

        // ******* INTERACTIONS *******

        // Success
        return true;
    }

}


