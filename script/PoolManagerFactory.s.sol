// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PoolManagerFactory} from "../src/PoolManagerFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {PoolManager} from "../src/PoolManager.sol";

contract DeployPoolManagerFactory is Script {
    address owner = address(0xE4f3B256c27cE7c76C5D16Ae81838aA14d8846C8);
    address strategyManager = address(0xE4f3B256c27cE7c76C5D16Ae81838aA14d8846C8);
    address WETH =0x4200000000000000000000000000000000000006;
    address USDC =0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address DAI =0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address USDT =0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    

    function deployPoolManagerAndTokens() public returns (address) {

        PoolManager poolManager = new PoolManager();

        bytes memory data = abi.encodeWithSelector(PoolManager.initialize.selector,owner,strategyManager,address(12));

        for(uint i=0;i<3;i++){
            ERC1967Proxy proxy = new ERC1967Proxy(address(poolManager), data);
            PoolManager(address(proxy)).registerAsset(WETH, "WETH", "WETH");
            PoolManager(address(proxy)).registerAsset(USDC, "USDC", "USDC");
            PoolManager(address(proxy)).registerAsset(DAI, "DAI", "DAI");
            PoolManager(address(proxy)).registerAsset(USDT, "USDT", "USDT");

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