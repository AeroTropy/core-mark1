// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IBundler, Call} from "@mark-Bundler/interfaces/IBundler.sol";
import {Bundler} from "@mark-Bundler/Bundler.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol"; 
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BundlerTest is Test {
    Bundler public bundler;
    PoolManager public poolManagerImpl;
    PoolManager public poolManager;
    ERC1967Proxy public proxy;
    
    ERC20Mock public token;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public strategyManager = address(0x3);
    
    uint256 public tokenId;
    
    function setUp() public {
        // Deploy bundler
        bundler = new Bundler();
        
        // Deploy implementation
        poolManagerImpl = new PoolManager();
        
        // Deploy proxy pointing to implementation
        bytes memory initData = abi.encodeWithSelector(
            poolManagerImpl.initialize.selector,
            owner,
            strategyManager,
            address(bundler)
        );
        proxy = new ERC1967Proxy(address(poolManagerImpl), initData);
        
        // Setup pool manager through proxy
        poolManager = PoolManager(address(proxy));
        
        // Deploy mock token
        token = new ERC20Mock("Test Token", "TEST", 18);
        
        // Mint some tokens to user
        token.mint(user, 1000 * 10**18);
        
        // Register asset
        vm.prank(owner);
        tokenId = poolManager.registerAsset(address(token), "Test Token", "TEST");
    }
    
    
    function testBundlerApproveAndDepositInOneTransaction() public {
        uint256 depositAmount = 100 * 10**18;
        
        // Verify user has no approval yet
        assertEq(token.allowance(user, address(poolManager)), 0, "User should start with zero allowance");
        
        // Create the approve calldata
        bytes memory approveCalldata = abi.encodeWithSelector(
            token.approve.selector,
            address(poolManager),
            depositAmount
        );
        
        // Create the deposit calldata
        bytes memory depositCalldata = abi.encodeWithSelector(
            poolManager.deposit.selector,
            tokenId,
            depositAmount,
            user  // Receiver is the user
        );
        
        // Create the bundle with approve + deposit
        Call[] memory bundle = new Call[](2);
        
        // First call: approve
        bundle[0] = Call({
            to: address(token),
            value: 0,
            data: approveCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        // Second call: deposit (this would fail without the preceding approve)
        bundle[1] = Call({
            to: address(poolManager),
            value: 0,
            data: depositCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        // Execute the bundle as user
        vm.prank(user);
        bundler.multicall(bundle);
        
        // Verify user received shares
        assertGt(poolManager.balanceOf(user, tokenId), 0, "User should have received shares");
        
        // Verify asset was transferred from the user
        assertEq(token.balanceOf(user), 900 * 10**18, "User balance should be reduced");
        assertEq(token.balanceOf(address(poolManager)), depositAmount, "Assets should be in the pool");
    }
    
    function testTransferAndRedeemInOneTransaction() public {
        // First deposit some tokens
        uint256 depositAmount = 100 * 10**18;
        vm.startPrank(user);
        token.approve(address(poolManager), depositAmount);
        poolManager.deposit(tokenId, depositAmount, user);
        uint256 sharesBalance = poolManager.balanceOf(user, tokenId);
        vm.stopPrank();
        
        address recipient = address(0x4);
        uint256 transferAmount = sharesBalance / 2;
        
        // Create transfer calldata
        bytes memory transferCalldata = abi.encodeWithSelector(
            poolManager.transfer.selector,
            recipient,
            tokenId,
            transferAmount
        );
        
        // Create redeem calldata for the remaining shares
        bytes memory redeemCalldata = abi.encodeWithSelector(
            poolManager.redeem.selector,
            tokenId,
            sharesBalance - transferAmount,
            user,
            user
        );
        
        // Create the bundle with transfer + redeem
        Call[] memory bundle = new Call[](2);
        
        bundle[0] = Call({
            to: address(poolManager),
            value: 0,
            data: transferCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        bundle[1] = Call({
            to: address(poolManager),
            value: 0,
            data: redeemCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        // Execute the bundle as user
        vm.prank(user);
        bundler.multicall(bundle);
        
        // Verify recipient received shares
        assertEq(poolManager.balanceOf(recipient, tokenId), transferAmount, "Recipient should have received shares");
        
        // Verify user redeemed their shares
        assertEq(poolManager.balanceOf(user, tokenId), 0, "User should have no shares left");
        
        // Verify token balances
        assertEq(token.balanceOf(user), 950 * 10**18, "User should have received half their tokens back");
        assertEq(token.balanceOf(address(poolManager)), depositAmount / 2, "Pool should have half the tokens left");
    }
    
    function testComplexMultiCallScenario() public {
        uint256 depositAmount = 100 * 10**18;
        address friend = address(0x5);
        
        // Mint some tokens to friend
        token.mint(friend, 1000 * 10**18);
        
        // Create token approval calldata
        bytes memory userApproveCalldata = abi.encodeWithSelector(
            token.approve.selector,
            address(poolManager),
            depositAmount
        );
        
        // Create deposit calldata
        bytes memory depositCalldata = abi.encodeWithSelector(
            poolManager.deposit.selector,
            tokenId,
            depositAmount,
            user
        );
        
        // Create operator approval calldata
        bytes memory setOperatorCalldata = abi.encodeWithSelector(
            poolManager.setOperator.selector,
            friend,
            true
        );
        
        // Create a bundle with multiple operations
        Call[] memory bundle = new Call[](3);
        
        bundle[0] = Call({
            to: address(token),
            value: 0,
            data: userApproveCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        bundle[1] = Call({
            to: address(poolManager),
            value: 0,
            data: depositCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        bundle[2] = Call({
            to: address(poolManager),
            value: 0,
            data: setOperatorCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        // Execute the bundle as user
        vm.prank(user);
        bundler.multicall(bundle);
        
        // Verify user received shares
        assertEq(poolManager.balanceOf(user, tokenId), depositAmount, "User should have received shares");
        
        // Verify friend is now an operator
        assertTrue(poolManager.isOperator(user, friend), "Friend should be an operator");
        
        // Now friend can transfer user's tokens through the bundler
        bytes memory transferFromCalldata = abi.encodeWithSelector(
            poolManager.transferFrom.selector,
            user,  // from
            friend, // to
            tokenId,
            depositAmount / 2
        );
        
        Call[] memory friendBundle = new Call[](1);
        friendBundle[0] = Call({
            to: address(poolManager),
            value: 0,
            data: transferFromCalldata,
            callbackHash: bytes32(0),
            skipRevert: false
        });
        
        // Execute as friend
        vm.prank(friend);
        bundler.multicall(friendBundle);
        
        // Verify transfer worked
        assertEq(poolManager.balanceOf(user, tokenId), depositAmount / 2, "User should have half the shares left");
        assertEq(poolManager.balanceOf(friend, tokenId), depositAmount / 2, "Friend should have half the shares");
    }
}