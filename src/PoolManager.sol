// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {MultiAssetVault} from './helpers/MultiAssetVault.sol';
import {CustomRevert} from './libraries/CustomRevert.sol';
import {IERC20} from './interfaces/IERC20.sol';
import {Initializable} from "@solady/utils/Initializable.sol";

contract PoolManager is UUPSUpgradeable, Ownable, MultiAssetVault, Initializable {
    using CustomRevert for bytes4;
    
    address public strategyManager;
    
    mapping(address asset => bool isRegistered) public registeredAssets;
    mapping(uint256 tokenId => uint256 allocatedToStrategy) public strategyAllocations;
    
    address[] public registeredAssetsList;
    
    error AssetAlreadyRegistered();
    error InvalidAllocationPercentage();
    error UnauthorizedCaller();
    error InsufficientAssets();
    
    event AssetRegistered(uint256 indexed tokenId, address indexed asset, string name, string symbol);
    event BatchFundsProvidedToStrategy(uint256[] tokenIds, address[] assets, uint256[] amounts);
    event BatchFundsReturnedFromStrategy(uint256[] tokenIds, address[] assets, uint256[] amounts);
    
    function initialize(address _owner, address _strategyManager) public initializer {
        _initializeOwner(_owner);
        strategyManager = _strategyManager;
    }
    
    modifier onlyStrategyManager() {
        if (msg.sender != strategyManager) UnauthorizedCaller.selector.revertWith();
        _;
    }
    
    function registerAsset(address asset, string memory name, string memory symbol) public onlyOwner returns(uint256 tokenId) {
        if (registeredAssets[asset]) AssetAlreadyRegistered.selector.revertWith();
        
        uint8 decimals = IERC20(asset).decimals();
        id++; // Use the inherited id counter from MultiAssetVault
        tokenId = id;
        
        idToAsset[tokenId] = asset;
        idToMetadata[tokenId] = TokenMetadata({
            name: name,
            symbol: symbol,
            decimals: decimals,
            underlyingAsset: asset,
            isRegistered: true
        });
        
        registeredAssets[asset] = true;
        registeredAssetsList.push(asset);
        
        emit AssetRegistered(tokenId, asset, name, symbol);
        
        return tokenId;
    }
    
    // Batch function for StrategyManager to pull multiple assets from the pool
    function provideBatchFundsToStrategy(
        uint256[] calldata tokenIds, 
        uint256[] calldata amounts
    ) external onlyStrategyManager returns (bool[] memory results) {
        if (tokenIds.length != amounts.length) revert("Array length mismatch");
        
        results = new bool[](tokenIds.length);
        address[] memory assets = new address[](tokenIds.length);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            address asset = idToAsset[tokenId];
            
            if (asset == address(0)) {
                results[i] = false;
                continue; // Skip invalid asset
            }
            
            uint256 availableAssets = totalAssets(tokenId) - strategyAllocations[tokenId];
            if (availableAssets < amounts[i]) {
                results[i] = false;
                continue; // Skip if not enough assets
            }
            
            // Transfer the assets to the strategy manager
            IERC20(asset).transfer(strategyManager, amounts[i]);
            
            // Update allocations
            strategyAllocations[tokenId] += amounts[i];
            results[i] = true;
            assets[i] = asset;
        }
        
        emit BatchFundsProvidedToStrategy(tokenIds, assets, amounts);
        
        return results;
    }
    
    // Batch function for StrategyManager to return multiple assets to the pool
    function receiveBatchFundsFromStrategy(
        uint256[] calldata tokenIds, 
        uint256[] calldata amounts
    ) external onlyStrategyManager returns (bool[] memory results) {
        if (tokenIds.length != amounts.length) revert("Array length mismatch");
        
        results = new bool[](tokenIds.length);
        address[] memory assets = new address[](tokenIds.length);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            address asset = idToAsset[tokenId];
            
            if (asset == address(0)) {
                results[i] = false;
                continue; // Skip invalid asset
            }
            
            // Update allocations
            if (amounts[i] <= strategyAllocations[tokenId]) {
                strategyAllocations[tokenId] -= amounts[i];
            } else {
                strategyAllocations[tokenId] = 0; // In case more is returned than was recorded
            }
            
            results[i] = true;
            assets[i] = asset;
        }
        
        emit BatchFundsReturnedFromStrategy(tokenIds, assets, amounts);
        
        return results;
    }
    
    // Get all registered assets with their token IDs
    function getRegisteredAssets() public view returns(
        uint256[] memory tokenIds, 
        address[] memory assets
    ) {
        tokenIds = new uint256[](registeredAssetsList.length);
        assets = new address[](registeredAssetsList.length);
        
        for (uint256 i = 0; i < registeredAssetsList.length; i++) {
            assets[i] = registeredAssetsList[i];
            
            // Find tokenId for this asset
            for (uint256 j = 1; j <= id; j++) {
                if (idToAsset[j] == assets[i]) {
                    tokenIds[i] = j;
                    break;
                }
            }
        }
        
        return (tokenIds, assets);
    }
    
    // Get information about all tokens with their allocations
    function getAllTokensInfo() public view returns(
        uint256[] memory tokenIds,
        address[] memory assets,
        uint256[] memory totalAssetsInPool,
        uint256[] memory allocatedToStrategy
    ) {
        tokenIds = new uint256[](id);
        assets = new address[](id);
        totalAssetsInPool = new uint256[](id);
        allocatedToStrategy = new uint256[](id);
        
        for (uint256 i = 1; i <= id; i++) {
            tokenIds[i-1] = i;
            assets[i-1] = idToAsset[i];
            totalAssetsInPool[i-1] = totalAssets(i);
            allocatedToStrategy[i-1] = strategyAllocations[i];
        }
        
        return (tokenIds, assets, totalAssetsInPool, allocatedToStrategy);
    }
    
    // Update strategy manager address
    function updateStrategyManager(address _newStrategyManager) external onlyOwner {
        strategyManager = _newStrategyManager;
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}