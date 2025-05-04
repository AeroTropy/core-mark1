// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {MultiAssetVault} from "../src/helpers/MultiAssetVault.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract StrategyManagerMock {
    function transferFrom(address token, address from, uint256 amount) external {
        IERC20(token).transferFrom(from, address(this), amount);
    }

    function transfer(address token, address to, uint256 amount) external {
        IERC20(token).transfer(to, amount);
    }
}

contract PoolManagerTest is Test {
    PoolManager public poolManager;
    StrategyManagerMock public strategyManager;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    ERC20Mock public token1;
    ERC20Mock public token2;
    ERC20Mock public token3;
    
    uint256 public token1Id;
    uint256 public token2Id;
    uint256 public token3Id;
    
    // Initial setup amounts
    uint256 constant INITIAL_MINT = 1_000_000 * 10**18;
    uint256 constant DEPOSIT_AMOUNT = 100_000 * 10**18;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token1 = new ERC20Mock("Token 1", "TK1", 18);
        token2 = new ERC20Mock("Token 2", "TK2", 18);
        token3 = new ERC20Mock("Token 3", "TK3", 6); // Different decimals
        
        // Deploy strategy manager mock
        strategyManager = new StrategyManagerMock();
        
        // Deploy pool manager
        poolManager = new PoolManager();
        poolManager.initialize(owner, address(strategyManager));
        
        // Register assets in the pool
        token1Id = poolManager.registerAsset(address(token1), "Token 1 Vault", "vTK1");
        token2Id = poolManager.registerAsset(address(token2), "Token 2 Vault", "vTK2");
        token3Id = poolManager.registerAsset(address(token3), "Token 3 Vault", "vTK3");
        
        // Mint tokens to users
        token1.mint(user1, INITIAL_MINT);
        token1.mint(user2, INITIAL_MINT);
        token2.mint(user1, INITIAL_MINT);
        token2.mint(user2, INITIAL_MINT);
        token3.mint(user1, INITIAL_MINT / 10**12); // Adjust for decimals
        token3.mint(user2, INITIAL_MINT / 10**12); // Adjust for decimals
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AssetRegistration() public {
        // Check that the assets were registered correctly
        (uint256[] memory tokenIds, address[] memory assets) = poolManager.getRegisteredAssets();
        
        assertEq(tokenIds.length, 3);
        assertEq(assets.length, 3);
        
        assertEq(tokenIds[0], token1Id);
        assertEq(tokenIds[1], token2Id);
        assertEq(tokenIds[2], token3Id);
        
        assertEq(assets[0], address(token1));
        assertEq(assets[1], address(token2));
        assertEq(assets[2], address(token3));
        
        // Check metadata
        assertEq(poolManager.name(token1Id), "Token 1 Vault");
        assertEq(poolManager.symbol(token1Id), "vTK1");
        assertEq(poolManager.decimals(token1Id), 18);
        
        assertEq(poolManager.name(token3Id), "Token 3 Vault");
        assertEq(poolManager.symbol(token3Id), "vTK3");
        assertEq(poolManager.decimals(token3Id), 6);
    }
    
    function test_Revert_DuplicateAssetRegistration() public {
        vm.startPrank(owner);
        // Try to register the same asset again, should fail
        vm.expectRevert();
        poolManager.registerAsset(address(token1), "Duplicate", "DTK");
        vm.stopPrank();
    }
    
    function test_Revert_UnauthorizedAssetRegistration() public {
        vm.startPrank(user1);
        // Try to register an asset as a non-owner, should fail
        vm.expectRevert();
        poolManager.registerAsset(address(0x1234), "Unauthorized Token", "UTK");
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit() public {
        vm.startPrank(user1);
        
        // Approve tokens
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        
        // Initial balances should be 0
        assertEq(poolManager.balanceOf(user1, token1Id), 0);
        assertEq(poolManager.totalSupply(token1Id), 0);
        assertEq(poolManager.totalAssets(token1Id), 0);
        
        // Deposit tokens
        uint256 shares = poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Check that shares were minted correctly
        assertEq(shares, DEPOSIT_AMOUNT); // Initial deposit is 1:1
        assertEq(poolManager.balanceOf(user1, token1Id), DEPOSIT_AMOUNT);
        assertEq(poolManager.totalSupply(token1Id), DEPOSIT_AMOUNT);
        
        // Check that assets were transferred correctly
        assertEq(token1.balanceOf(address(poolManager)), DEPOSIT_AMOUNT);
        assertEq(poolManager.totalAssets(token1Id), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_DepositToOtherAddress() public {
        vm.startPrank(user1);
        
        // Approve tokens
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        
        // Deposit tokens to user2's address
        uint256 shares = poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user2);
        
        // Check that shares were minted correctly to user2
        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(poolManager.balanceOf(user2, token1Id), DEPOSIT_AMOUNT);
        assertEq(poolManager.balanceOf(user1, token1Id), 0);
        
        vm.stopPrank();
    }
    
    function test_MultipleDeposits() public {
        vm.startPrank(user1);
        
        // Approve tokens
        token1.approve(address(poolManager), DEPOSIT_AMOUNT * 2);
        
        // First deposit
        uint256 shares1 = poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Second deposit
        uint256 shares2 = poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Check totals
        assertEq(poolManager.balanceOf(user1, token1Id), DEPOSIT_AMOUNT * 2);
        assertEq(poolManager.totalSupply(token1Id), DEPOSIT_AMOUNT * 2);
        assertEq(poolManager.totalAssets(token1Id), DEPOSIT_AMOUNT * 2);
        
        vm.stopPrank();
    }
    
    function test_Revert_DepositInvalidToken() public {
        vm.startPrank(user1);
        
        // Try to deposit with an invalid token ID
        vm.expectRevert();
        poolManager.deposit(999, DEPOSIT_AMOUNT, user1);
        
        vm.stopPrank();
    }
    
    function test_Revert_DepositZeroAmount() public {
        vm.startPrank(user1);
        
        // Try to deposit zero amount
        vm.expectRevert();
        poolManager.deposit(token1Id, 0, user1);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Withdraw() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Initial balance should match deposit
        uint256 initialBalance = token1.balanceOf(user1);
        
        // Withdraw all tokens
        uint256 assets = poolManager.withdraw(token1Id, DEPOSIT_AMOUNT, user1, user1);
        
        // Check that assets were withdrawn correctly
        assertEq(assets, DEPOSIT_AMOUNT);
        assertEq(token1.balanceOf(user1), initialBalance + DEPOSIT_AMOUNT);
        
        // Check that shares were burned correctly
        assertEq(poolManager.balanceOf(user1, token1Id), 0);
        assertEq(poolManager.totalSupply(token1Id), 0);
        assertEq(poolManager.totalAssets(token1Id), 0);
        
        vm.stopPrank();
    }
    
    function test_Redeem() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Initial balance should match deposit
        uint256 initialBalance = token1.balanceOf(user1);
        
        // Redeem all shares
        uint256 assets = poolManager.redeem(token1Id, DEPOSIT_AMOUNT, user1, user1);
        
        // Check that assets were redeemed correctly
        assertEq(assets, DEPOSIT_AMOUNT);
        assertEq(token1.balanceOf(user1), initialBalance + DEPOSIT_AMOUNT);
        
        // Check that shares were burned correctly
        assertEq(poolManager.balanceOf(user1, token1Id), 0);
        assertEq(poolManager.totalSupply(token1Id), 0);
        assertEq(poolManager.totalAssets(token1Id), 0);
        
        vm.stopPrank();
    }
    
    // function test_WithdrawToOtherAddress() public {
    //     // First deposit some tokens
    //     vm.startPrank(user1);
    //     token1.approve(address(poolManager), DEPOSIT_AMOUNT);
    //     poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
    //     // Initial balances
    //     uint256 user1InitialBalance = token1.balanceOf(user1);
    //     uint256 user2InitialBalance = token1.balanceOf(user2);
        
    //     // Withdraw to user2's address
    //     uint256 assets = poolManager.withdraw(token1Id, DEPOSIT_AMOUNT / 2, user2, user1);
        
    //     // Check that assets were withdrawn correctly to user2
    //     assertEq(assets, DEPOSIT_AMOUNT / 2);
    //     assertEq(token1.balanceOf(user2), user2InitialBalance + DEPOSIT_AMOUNT / 2);
    //     assertEq(token1.balanceOf(user1), user1InitialBalance); // User1's balance unchanged
        
    //     // Check that shares were burned correctly
    //     assertEq(poolManager.balanceOf(user1, token1Id), DEPOSIT_AMOUNT / 2);
    //     assertEq(poolManager.totalSupply(token1Id), DEPOSIT_AMOUNT / 2);
        
    //     vm.stopPrank();
    // }
    
    function test_PartialWithdrawal() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Initial balance
        uint256 initialBalance = token1.balanceOf(user1);
        
        // Withdraw half the tokens
        uint256 assets = poolManager.withdraw(token1Id, DEPOSIT_AMOUNT / 2, user1, user1);
        
        // Check that assets were withdrawn correctly
        assertEq(assets, DEPOSIT_AMOUNT / 2);
        assertEq(token1.balanceOf(user1), initialBalance + DEPOSIT_AMOUNT / 2);
        
        // Check that shares were burned correctly
        assertEq(poolManager.balanceOf(user1, token1Id), DEPOSIT_AMOUNT / 2);
        assertEq(poolManager.totalSupply(token1Id), DEPOSIT_AMOUNT / 2);
        assertEq(poolManager.totalAssets(token1Id), DEPOSIT_AMOUNT / 2);
        
        vm.stopPrank();
    }
    
    function test_Revert_WithdrawInvalidToken() public {
        vm.startPrank(user1);
        
        // Try to withdraw with an invalid token ID
        vm.expectRevert();
        poolManager.withdraw(999, DEPOSIT_AMOUNT, user1, user1);
        
        vm.stopPrank();
    }
    
    function test_Revert_WithdrawTooMuch() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);

        vm.expectRevert();
        
        // Try to withdraw more than deposited
        poolManager.withdraw(token1Id, DEPOSIT_AMOUNT * 2, user1, user1);
        
        vm.stopPrank();
    }
    
    function test_Revert_UnauthorizedWithdrawal() public {
        // First deposit some tokens as user1
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Try to withdraw as user2
        vm.startPrank(user2);
        
        vm.expectRevert();
        
        poolManager.withdraw(token1Id, DEPOSIT_AMOUNT, user2, user1);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          MINTING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Mint() public {
        vm.startPrank(user1);
        
        // Approve tokens
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        
        // Mint shares
        uint256 assets = poolManager.mint(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Check that shares were minted correctly
        assertEq(assets, DEPOSIT_AMOUNT); // Initial mint is 1:1
        assertEq(poolManager.balanceOf(user1, token1Id), DEPOSIT_AMOUNT);
        assertEq(poolManager.totalSupply(token1Id), DEPOSIT_AMOUNT);
        
        // Check that assets were transferred correctly
        assertEq(token1.balanceOf(address(poolManager)), DEPOSIT_AMOUNT);
        assertEq(poolManager.totalAssets(token1Id), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                       STRATEGY ALLOCATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ProvideFundsToStrategy() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        token2.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        poolManager.deposit(token2Id, DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Prepare batch data
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = token1Id;
        tokenIds[1] = token2Id;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = DEPOSIT_AMOUNT / 2;
        amounts[1] = DEPOSIT_AMOUNT / 4;
        
        // Simulate strategy manager requesting funds
        vm.startPrank(address(strategyManager));
        bool[] memory results = poolManager.provideBatchFundsToStrategy(tokenIds, amounts);
        vm.stopPrank();
        
        // Check results
        assertTrue(results[0]);
        assertTrue(results[1]);
        
        // Check allocations
        assertEq(poolManager.strategyAllocations(token1Id), DEPOSIT_AMOUNT / 2);
        assertEq(poolManager.strategyAllocations(token2Id), DEPOSIT_AMOUNT / 4);
        
        // Check token balances
        assertEq(token1.balanceOf(address(strategyManager)), DEPOSIT_AMOUNT / 2);
        assertEq(token2.balanceOf(address(strategyManager)), DEPOSIT_AMOUNT / 4);
        
        // Check pool balances
        assertEq(token1.balanceOf(address(poolManager)), DEPOSIT_AMOUNT / 2);
        assertEq(token2.balanceOf(address(poolManager)), DEPOSIT_AMOUNT * 3 / 4);
    }
    
    function test_ReturnFundsFromStrategy() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        token2.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        poolManager.deposit(token2Id, DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Provide funds to strategy
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = token1Id;
        tokenIds[1] = token2Id;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = DEPOSIT_AMOUNT / 2;
        amounts[1] = DEPOSIT_AMOUNT / 4;
        
        vm.startPrank(address(strategyManager));
        poolManager.provideBatchFundsToStrategy(tokenIds, amounts);
        
        // Now return some funds
        uint256[] memory returnAmounts = new uint256[](2);
        returnAmounts[0] = DEPOSIT_AMOUNT / 4; // Half of what was allocated
        returnAmounts[1] = DEPOSIT_AMOUNT / 8; // Half of what was allocated
        
        // First transfer tokens back to the pool
        token1.transfer(address(poolManager), returnAmounts[0]);
        token2.transfer(address(poolManager), returnAmounts[1]);
        
        // Now record the return
        bool[] memory results = poolManager.receiveBatchFundsFromStrategy(tokenIds, returnAmounts);
        vm.stopPrank();
        
        // Check results
        assertTrue(results[0]);
        assertTrue(results[1]);
        
        // Check allocations
        assertEq(poolManager.strategyAllocations(token1Id), DEPOSIT_AMOUNT / 4); // Reduced by half
        assertEq(poolManager.strategyAllocations(token2Id), DEPOSIT_AMOUNT / 8); // Reduced by half
        
        // Check pool total assets - should include returned funds
        assertEq(poolManager.totalAssets(token1Id), DEPOSIT_AMOUNT * 3 / 4); // Original 50% + returned 25%
        assertEq(poolManager.totalAssets(token2Id), DEPOSIT_AMOUNT * 7 / 8); // Original 75% + returned 12.5%
    }
    
    function test_Revert_UnauthorizedFundProvision() public {
        // First deposit some tokens
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
        
        // Try to provide funds as non-strategy manager
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = token1Id;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEPOSIT_AMOUNT / 2;
        
        vm.expectRevert();
        
        poolManager.provideBatchFundsToStrategy(tokenIds, amounts);
        vm.stopPrank();
    }
    
    function test_FundProvision() public {
        // First deposit a small amount
        vm.startPrank(user1);
        token1.approve(address(poolManager), DEPOSIT_AMOUNT / 10);
        poolManager.deposit(token1Id, DEPOSIT_AMOUNT / 10, user1);
        vm.stopPrank();
        
        // Try to provide more funds than available
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = token1Id;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEPOSIT_AMOUNT; // More than deposited
        
        
        vm.startPrank(address(strategyManager));
        bool[] memory results = poolManager.provideBatchFundsToStrategy(tokenIds, amounts);
        vm.stopPrank();
        
        // Should fail and return false
        assertFalse(results[0]);
        
        // Allocation should remain 0
        assertEq(poolManager.strategyAllocations(token1Id), 0);
    }
    
    function test_UpdateStrategyManager() public {
        address newStrategyManager = address(0x999);
        
        // Update strategy manager
        vm.startPrank(owner);
        poolManager.updateStrategyManager(newStrategyManager);
        vm.stopPrank();
        
        // Check that it was updated
        assertEq(poolManager.strategyManager(), newStrategyManager);
    }
    
    function test_Revert_UnauthorizedUpdateStrategyManager() public {
        address newStrategyManager = address(0x999);
        
        // Try to update strategy manager as non-owner
        vm.startPrank(user1);
        vm.expectRevert();
        poolManager.updateStrategyManager(newStrategyManager);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    // function test_GetAllTokensInfo() public {
    //     // First deposit some tokens
    //     vm.startPrank(user1);
    //     token1.approve(address(poolManager), DEPOSIT_AMOUNT);
    //     token2.approve(address(poolManager), DEPOSIT_AMOUNT);
    //     poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
    //     poolManager.deposit(token2Id, DEPOSIT_AMOUNT, user1);
    //     vm.stopPrank();
        
    //     // Allocate some to strategy
    //     uint256[] memory tokenIds = new uint256[](2);
    //     tokenIds[0] = token1Id;
    //     tokenIds[1] = token2Id;
        
    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = DEPOSIT_AMOUNT / 2;
    //     amounts[1] = DEPOSIT_AMOUNT / 4;
        
    //     vm.startPrank(address(strategyManager));
    //     poolManager.provideBatchFundsToStrategy(tokenIds, amounts);
    //     vm.stopPrank();
        
    //     // Get all tokens info
    //     (
    //         uint256[] memory infoTokenIds,
    //         address[] memory assets,
    //         uint256[] memory totalAssetsInPool,
    //         uint256[] memory allocatedToStrategy
    //     ) = poolManager.getAllTokensInfo();
        
    //     // Check results - array lengths should match
    //     assertEq(infoTokenIds.length, 3); // We registered 3 tokens
    //     assertEq(assets.length, 3);
    //     assertEq(totalAssetsInPool.length, 3);
    //     assertEq(allocatedToStrategy.length, 3);
        
    //     // Check token1 info
    //     assertEq(infoTokenIds[token1Id - 1], token1Id);
    //     assertEq(assets[token1Id - 1], address(token1));
    //     assertEq(totalAssetsInPool[token1Id - 1], DEPOSIT_AMOUNT);
    //     assertEq(allocatedToStrategy[token1Id - 1], DEPOSIT_AMOUNT / 2);
        
    //     // Check token2 info
    //     assertEq(infoTokenIds[token2Id - 1], token2Id);
    //     assertEq(assets[token2Id - 1], address(token2));
    //     assertEq(totalAssetsInPool[token2Id - 1], DEPOSIT_AMOUNT);
    //     assertEq(allocatedToStrategy[token2Id - 1], DEPOSIT_AMOUNT / 4);
        
    //     // Check token3 info (no deposits)
    //     assertEq(infoTokenIds[token3Id - 1], token3Id);
    //     assertEq(assets[token3Id - 1], address(token3));
    //     assertEq(totalAssetsInPool[token3Id - 1], 0);
    //     assertEq(allocatedToStrategy[token3Id - 1], 0);
    // }
    
    // function test_ConversionFunctions() public {
    //     // First deposit some tokens
    //     vm.startPrank(user1);
    //     token1.approve(address(poolManager), DEPOSIT_AMOUNT);
    //     poolManager.deposit(token1Id, DEPOSIT_AMOUNT, user1);
    //     vm.stopPrank();
        
    //     // Test conversion functions with 1:1 ratio
    //     assertEq(poolManager.convertToShares(token1Id, DEPOSIT_AMOUNT / 2), DEPOSIT_AMOUNT / 2);
    //     assertEq(poolManager.convertToAssets(token1Id, DEPOSIT_AMOUNT / 2), DEPOSIT_AMOUNT / 2);
        
    //     // Simulate yield generation by transferring extra tokens to the pool
    //     // This will change the share/asset ratio
    //     token1.mint(address(poolManager), DEPOSIT_AMOUNT); // 100% yield
        
    //     // Now the conversion ratio should be 1:2 (shares:assets)
    //     // 1 share = 2 assets
    //     assertEq(poolManager.convertToShares(token1Id, DEPOSIT_AMOUNT), DEPOSIT_AMOUNT / 2);
    //     assertEq(poolManager.convertToAssets(token1Id, DEPOSIT_AMOUNT / 2), DEPOSIT_AMOUNT);
        
    //     // Test preview functions
    //     assertEq(poolManager.previewDeposit(token1Id, DEPOSIT_AMOUNT), DEPOSIT_AMOUNT / 2);
    //     assertEq(poolManager.previewMint(token1Id, DEPOSIT_AMOUNT / 2), DEPOSIT_AMOUNT);
    //     assertEq(poolManager.previewRedeem(token1Id, DEPOSIT_AMOUNT / 2), DEPOSIT_AMOUNT);
    //     assertEq(poolManager.previewWithdraw(token1Id, DEPOSIT_AMOUNT), DEPOSIT_AMOUNT / 2);
    // }
}