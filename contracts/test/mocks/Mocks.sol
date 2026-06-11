// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEscrowMarket} from "../../src/interfaces/IEscrowMarket.sol";

/// @dev Plain 6-decimals token (USDC-like).
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev USDC-like token with an owner-set blocklist: transfers to blocked
///      addresses revert (mirrors Circle's blocklist behavior).
contract BlocklistToken is MockERC20 {
    mapping(address => bool) public blocked;

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to] && !blocked[from], "BlocklistToken: blocked");
        super._update(from, to, value);
    }
}

/// @dev Token that returns false instead of reverting on failed transfers,
///      and true otherwise but WITHOUT reverting on a "soft-fail" list.
contract ReturnFalseToken is MockERC20 {
    mapping(address => bool) public softFail;

    function setSoftFail(address account, bool fails) external {
        softFail[account] = fails;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (softFail[to]) return false;
        return super.transfer(to, value);
    }
}

/// @dev Fee-on-transfer token: recipient receives less than sent.
contract FeeOnTransferToken is MockERC20 {
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 1) {
            super._update(from, address(0xdead), 1); // skim 1 unit
            super._update(from, to, value - 1);
        } else {
            super._update(from, to, value);
        }
    }
}

/// @dev ETH recipient whose acceptance can be toggled; can act as buyer or
///      seller through the market.
contract ToggleReceiver {
    bool public accept = true;

    function setAccept(bool accept_) external {
        accept = accept_;
    }

    receive() external payable {
        require(accept, "ToggleReceiver: rejecting");
    }

    function doBuy(IEscrowMarket market, uint256 listingId) external payable returns (uint256) {
        return market.buy{value: msg.value}(listingId);
    }

    function doCreateListing(IEscrowMarket market, uint96 price) external returns (uint256) {
        return market.createListing(address(0), price, bytes32("cat"), "cid");
    }

    function doWithdraw(IEscrowMarket market) external {
        market.withdraw(address(0));
    }
}

/// @dev Malicious ETH recipient that attempts to re-enter the market on
///      receive. Any reentrant call reverting must NOT block the payout path
///      (the market falls back to queueing only if the transfer fails).
contract ReentrantReceiver {
    IEscrowMarket public market;
    uint256 public escrowId;
    bool public attack;
    bool public reentryBlocked;

    constructor(IEscrowMarket market_) {
        market = market_;
    }

    function setAttack(uint256 escrowId_, bool attack_) external {
        escrowId = escrowId_;
        attack = attack_;
    }

    function doBuy(uint256 listingId) external payable returns (uint256) {
        return market.buy{value: msg.value}(listingId);
    }

    receive() external payable {
        if (attack) {
            attack = false;
            try market.release(escrowId) {
                reentryBlocked = false;
            } catch {
                reentryBlocked = true;
            }
        }
    }
}
