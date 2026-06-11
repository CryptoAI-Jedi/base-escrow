// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EscrowMarket} from "../src/EscrowMarket.sol";

/// @notice Deploys EscrowMarket and writes the address artifact consumed by
///         the web app, indexer, and resolver configs.
///
/// Required env:
///   RESOLVER_ADDRESS   — CRE/resolver signer (the only address that can resolve)
///   TREASURY_ADDRESS   — protocol fee recipient
/// Optional env:
///   OWNER_ADDRESS           — final owner (2-step; defaults to the deployer)
///   USDC_ADDRESS            — ERC-20 to whitelist (Base Sepolia USDC:
///                             0x036CbD53842c5426634e7929541eC2318f3dCF7e)
///   RELEASE_WINDOW          — seconds until auto-release (default 7 days)
///   SELLER_RESPONSE_WINDOW  — seconds for seller to answer a dispute (default 3 days)
///
/// Usage:
///   forge script script/Deploy.s.sol --rpc-url base-sepolia --broadcast --verify
contract Deploy is Script {
    function run() external returns (EscrowMarket market) {
        address resolver_ = vm.envAddress("RESOLVER_ADDRESS");
        address treasury_ = vm.envAddress("TREASURY_ADDRESS");
        uint64 releaseWindow = uint64(vm.envOr("RELEASE_WINDOW", uint256(7 days)));
        uint64 responseWindow = uint64(vm.envOr("SELLER_RESPONSE_WINDOW", uint256(3 days)));
        address usdc = vm.envOr("USDC_ADDRESS", address(0));

        vm.startBroadcast();
        address deployer = msg.sender;
        address finalOwner = vm.envOr("OWNER_ADDRESS", deployer);

        // Deploy with the deployer as owner so post-deploy config works in
        // one broadcast; hand over (2-step) at the end if a separate owner
        // was requested.
        market = new EscrowMarket(deployer, resolver_, treasury_, releaseWindow, responseWindow);

        if (usdc != address(0)) {
            market.setToken(usdc, true);
        }

        if (finalOwner != deployer) {
            market.transferOwnership(finalOwner); // finalOwner must call acceptOwnership()
        }
        vm.stopBroadcast();

        console.log("EscrowMarket deployed:", address(market));
        console.log("  resolver:", resolver_);
        console.log("  treasury:", treasury_);
        console.log("  releaseWindow (s):", releaseWindow);
        console.log("  sellerResponseWindow (s):", responseWindow);
        if (usdc != address(0)) console.log("  whitelisted token:", usdc);
        if (finalOwner != deployer) console.log("  pending owner (must accept):", finalOwner);

        string memory json = "deployment";
        vm.serializeAddress(json, "escrowMarket", address(market));
        vm.serializeAddress(json, "resolver", resolver_);
        vm.serializeAddress(json, "treasury", treasury_);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory out = vm.serializeUint(json, "deployBlock", block.number);
        vm.writeJson(out, string.concat("deployments/", vm.toString(block.chainid), ".json"));
    }
}
