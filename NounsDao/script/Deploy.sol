// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {FullRange} from "../contracts/FullRange.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {console} from "forge-std/console.sol";

contract DeployFullRangeNouns is Script {
    function run() external {
        address poolManagerAddress = 0x40a081A39E9638fa6e2463B92A4eff4Bdf877179;

        vm.startBroadcast();
        FullRange fullRangeNouns = new FullRange(IPoolManager(poolManagerAddress));
        vm.stopBroadcast();

        console.log("FullRange deployed at:", address(fullRangeNouns));
    }
}