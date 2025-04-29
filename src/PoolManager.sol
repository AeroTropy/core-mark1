// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStrategyManger} from "./interfaces/IStrategyManger.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {MultiAssetVault} from './helpers/MultiAssetVault.sol';
import {CustomRevert} from './libraries/CustomRevert.sol';
import {IERC20} from './interfaces/IERC20.sol';

abstract contract PoolManager is UUPSUpgradeable, Ownable,MultiAssetVault {
    using CustomRevert for bytes4;

    IStrategyManger strategyManager;

    mapping(address asset=>bool isRegistered) public registeredAssets;

    error AssetAlreadyRegistered();

    constructor(address _owner, address _strategyManager) {
        _initializeOwner(_owner);
        strategyManager = IStrategyManger(_strategyManager);
    }

   
   
   
   function registerAsset(address asset,string memory name,string memory symbol) public returns(uint256 tokenId) {
        if (registeredAssets[asset]) AssetAlreadyRegistered.selector.revertWith();
        uint8 decimals = IERC20(asset).decimals();
        tokenId++;
        idToAsset[tokenId] = asset;
        idToMetadata[tokenId] = TokenMetadata({
            name: name,
            symbol: symbol,
            decimals: decimals,
            underlyingAsset: asset,
            isRegistered: true
        });
        registeredAssets[asset] = true;
    }


    function transferAssetToStrategy() external returns(uint256[] memory ,address[] memory){

        for(uint i=0;i<=id;i++){
            
            
        }



    }

    function transferToStrategyManager(address asset, uint256 amount) public {}

    function getRegisteredAsset() public view returns(address[] memory){}

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}


