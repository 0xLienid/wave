// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {VestingManager} from "src/VestingManager.sol";

contract OTCEscrow {
    // ------ ERRORS ------ //

    error NotOwner();
    error NotTradeParticipant();
    error NotFunded();
    error AlreadyFunded();
    error Canceled();
    error Executed();

    // ------ EVENTS ------ //

    event TradeCreated(
        uint256 indexed tradeId,
        address indexed buyer,
        address indexed seller
    );

    event TradeFunded(uint256 indexed tradeId);

    event TradeCanceled(uint256 indexed tradeId);

    event TradeExecuted(uint256 indexed tradeId);

    // ------ DATA STRUCTURES ------ //

    struct Trade {
        VestingManager.VestType vestType;
        address buyer;
        address seller;
        address buyToken;
        uint256 buyAmount;
        uint256 sellClaimId;
        uint256 sellAmount;
        bool buyerFunded;
        bool sellerFunded;
        bool canceled;
        bool executed;
    }

    // ------ STATE VARIABLES ------ //

    address public owner;
    uint256 public fee; // Out of 1_000_000

    VestingManager public vestingManager;

    Trade[] public trades;

    constructor(uint256 fee_, address vestingManager_) {
        owner = msg.sender;
        fee = fee_;
        vestingManager = VestingManager(vestingManager_);
    }

    // ------ MODIFIERS ------ //

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ------ TRADE FUNCTIONS ------ //

    function newTrade(
        VestingManager.VestType type_,
        address buyer_,
        address seller_,
        address buyToken_,
        uint256 buyAmount_,
        uint256 sellClaimId_,
        uint256 sellAmount_
    ) external returns (uint256) {
        uint256 tradeId = trades.length;
        trades.push(
            Trade({
                vestType: type_,
                buyer: buyer_,
                seller: seller_,
                buyToken: buyToken_,
                buyAmount: buyAmount_,
                sellClaimId: sellClaimId_,
                sellAmount: sellAmount_,
                buyerFunded: false,
                sellerFunded: false,
                canceled: false,
                executed: false
            })
        );
        emit TradeCreated(tradeId, buyer_, seller_);
        return tradeId;
    }

    function fundTrade(uint256 tradeId_) external {
        Trade storage trade = trades[tradeId_];
        
        if (msg.sender != trade.buyer && msg.sender != trade.seller) revert NotTradeParticipant();
        if (trade.buyerFunded && trade.sellerFunded) revert AlreadyFunded();
        if (trade.canceled) revert Canceled();
        if (trade.executed) revert Executed();

        if (msg.sender == trade.buyer) {
            ERC20(trade.buyToken).transferFrom(msg.sender, address(this), trade.buyAmount);
        } else {
            vestingManager.transferFrom(trade.vestType, trade.sellClaimId, trade.seller, address(this), trade.sellAmount);
        }
    }

    function cancelTrade(uint256 tradeId_) external {
        Trade storage trade = trades[tradeId_];
        if (msg.sender != trade.buyer && msg.sender != trade.seller) revert NotTradeParticipant();
        if (trade.canceled) revert Canceled();
        if (trade.executed) revert Executed();

        trade.canceled = true;

        if (trade.buyerFunded) {
            ERC20(trade.buyToken).transfer(trade.buyer, trade.buyAmount);
        } else if (trade.sellerFunded) {
            vestingManager.transfer(trade.vestType, trade.sellClaimId, trade.seller, trade.sellAmount);
        }

        emit TradeCanceled(tradeId_);
    }

    function executeTrade(uint256 tradeId_) external {
        Trade storage trade = trades[tradeId_];
        if (msg.sender != trade.buyer && msg.sender != trade.seller) revert NotTradeParticipant();
        if (trade.canceled) revert Canceled();
        if (trade.executed) revert Executed();
        if (!trade.buyerFunded || !trade.sellerFunded) revert NotFunded();

        trade.executed = true;

        ERC20(trade.buyToken).transfer(owner, trade.buyAmount * fee / 1_000_000);
        ERC20(trade.buyToken).transfer(trade.seller, trade.buyAmount - trade.buyAmount * fee / 1_000_000);
        vestingManager.transfer(trade.vestType, trade.sellClaimId, trade.buyer, trade.sellAmount);

        emit TradeExecuted(tradeId_);
    }
}