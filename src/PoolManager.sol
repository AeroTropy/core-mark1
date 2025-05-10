// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {MultiAssetVault} from './helpers/MultiAssetVault.sol';
import {CustomRevert} from './libraries/CustomRevert.sol';
import {IERC20} from './interfaces/IERC20.sol';
import {Initializable} from "@solady/utils/Initializable.sol";
import {IBundler} from '@mark-Bundler/interfaces/IBundler.sol';

contract PoolManager is Initializable, UUPSUpgradeable, Ownable, MultiAssetVault {
    using CustomRevert for bytes4;
    
    address public strategyManager;

    address public bundler;
    
    mapping(address asset => bool isRegistered) public registeredAssets;
    mapping(uint256 tokenId => uint256 allocatedToStrategy) public strategyAllocations;
    
    address[] public registeredAssetsList;
    
    error AssetAlreadyRegistered();
    error InvalidAllocationPercentage();
    error UnauthorizedCaller();
    error InsufficientAssets();
    error ArrayLengthMismatch();
    error InvalidBundlerImplementation();
    
    event AssetRegistered(uint256 indexed tokenId, address indexed asset, string name, string symbol);
    event BatchFundsProvidedToStrategy(uint256[] tokenIds, address[] assets, uint256[] amounts);
    event BatchFundsReturnedFromStrategy(uint256[] tokenIds, address[] assets, uint256[] amounts);
    event BundlerAddressUpdated(address oldBundler, address newBundler);
    
    function initialize(address _owner, address _strategyManager, address _bundler) public initializer {
        _initializeOwner(_owner);
        strategyManager = _strategyManager;
        bundler = _bundler;
    }
    
    function _getActualCaller() internal view returns (address) {
        if (msg.sender == bundler && bundler != address(0)) {
            return IBundler(bundler).initiator();
        }
        return msg.sender;
    }
    
    function _checkOwner() internal view virtual override {
        if (_getActualCaller() != owner()) {
            revert("Not owner");
        }
    }
    
    modifier onlyStrategyManager() {
        if (_getActualCaller() != strategyManager) UnauthorizedCaller.selector.revertWith();
        _;
    }

    
    function deposit(uint256 tokenId, uint256 assets, address receiver) public payable returns (uint256) {
        return super.deposit(tokenId, assets, _getActualCaller(), receiver);
    }
    
    function mint(uint256 tokenId, uint256 shares, address receiver) public payable returns (uint256) {
        return super.mint(tokenId, shares, _getActualCaller(), receiver);
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
    
    function provideBatchFundsToStrategy(
        uint256[] calldata tokenIds, 
        uint256[] calldata amounts
    ) external onlyStrategyManager returns (bool[] memory results) {
        if (tokenIds.length != amounts.length) revert ArrayLengthMismatch();
        
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
    
    function receiveBatchFundsFromStrategy(
        uint256[] calldata tokenIds, 
        uint256[] calldata amounts
    ) external onlyStrategyManager returns (bool[] memory results) {
        if (tokenIds.length != amounts.length) revert ArrayLengthMismatch();
        
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
    
    function updateStrategyManager(address _newStrategyManager) external onlyOwner {
        strategyManager = _newStrategyManager;
    }
    
    function validateBundler(address _bundler) internal view returns (bool) {
        if (_bundler == address(0)) return true;
        
        try IBundler(_bundler).initiator() returns (address) {
            return true;
        } catch {
            return false;
        }
    }
    
    function updateBundler(address _newBundler) external onlyOwner {
        if (!validateBundler(_newBundler)) revert InvalidBundlerImplementation();
        
        address oldBundler = bundler;
        bundler = _newBundler;
        emit BundlerAddressUpdated(oldBundler, _newBundler);
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}