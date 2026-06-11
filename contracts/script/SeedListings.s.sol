// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EscrowMarket} from "../src/EscrowMarket.sol";

/// @notice Seeds demo listings on a fresh testnet deployment.
///
/// Required env:
///   ESCROW_MARKET_ADDRESS — deployed EscrowMarket
///
/// Usage:
///   forge script script/SeedListings.s.sol --rpc-url base-sepolia --broadcast
contract SeedListings is Script {
    function run() external {
        EscrowMarket market = EscrowMarket(vm.envAddress("ESCROW_MARKET_ADDRESS"));

        // Placeholder CIDs — replace with real pinned metadata when seeding
        // for the demo UI.
        vm.startBroadcast();
        market.createListing(
            address(0), 0.001 ether, keccak256("electronics"), "bafkreidemoelectronics"
        );
        market.createListing(address(0), 0.0005 ether, keccak256("collectibles"), "bafkreidemocollectible");
        market.createListing(address(0), 0.002 ether, keccak256("services"), "bafkreidemoservice");
        vm.stopBroadcast();

        console.log("Seeded 3 listings on", address(market));
        console.log("nextListingId:", market.nextListingId());
    }
}
