// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStrategyManger} from "./interfaces/IStrategyManger.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

abstract contract PoolManager is UUPSUpgradeable, Ownable {
    IStrategyManger strategyManager;

    constructor(address _owner, address _strategyManager) {
        _initializeOwner(_owner);
        strategyManager = IStrategyManger(_strategyManager);
    }

    function registerAsset(address asset) public {}

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
