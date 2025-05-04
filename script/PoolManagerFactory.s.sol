// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PoolManagerFactory} from "../src/PoolManagerFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {PoolManager} from "../src/PoolManager.sol";

contract DeployPoolManagerFactory is Script {
    address owner = address(0x641BB2596D8c0b32471260712566BF933a2f1a8e);
    address strategyManager = address(0x641BB2596D8c0b32471260712566BF933a2f1a8e);
    ERC20Mock public mockWETH;
    ERC20Mock public mockUSDC;  
    ERC20Mock public mockDAI;
    ERC20Mock public mockUSDT;
    

    function deployPoolManagerAndTokens() public returns (address) {

        PoolManager poolManager = new PoolManager();

        mockWETH = new ERC20Mock("WETH", "WETH", 18);
        mockUSDC = new ERC20Mock("USDC", "USDC", 6);
        mockDAI = new ERC20Mock("DAI", "DAI", 18);
        mockUSDT = new ERC20Mock("USDT", "USDT", 6);    

        vm.label(address(mockWETH), "MockWETH");
        vm.label(address(mockUSDC), "MockUSDC");
        vm.label(address(mockDAI), "MockDAI");
        vm.label(address(mockUSDT), "MockUSDT");

        bytes memory data = abi.encodeWithSelector(PoolManager.initialize.selector,owner,strategyManager);

        for(uint i=0;i<3;i++){
            ERC1967Proxy proxy = new ERC1967Proxy(address(poolManager), data);
            PoolManager(address(proxy)).registerAsset(address(mockWETH), "WETH", "WETH");
            PoolManager(address(proxy)).registerAsset(address(mockUSDC), "USDC", "USDC");
            PoolManager(address(proxy)).registerAsset(address(mockDAI), "DAI", "DAI");
            PoolManager(address(proxy)).registerAsset(address(mockUSDT), "USDT", "USDT");

            vm.label(address(proxy), "PoolManagerProxy");
        }


    }



    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        deployPoolManagerAndTokens();
        vm.stopBroadcast();
    }

    //source .env && forge script script/PoolManagerFactory.s.sol:DeployPoolManagerFactory --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
}