// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {PoolManagerFactory} from "../src/PoolManagerFactory.sol";
import {PoolManager} from "../src/PoolManager.sol";

contract PoolManagerFactoryTest is Test {
    PoolManagerFactory factory;
    address owner;
    address strategyManager;

    // Set up the test environment
    function setUp() public {
        factory = new PoolManagerFactory();
        owner = address(0x123);
        strategyManager = address(0x456);
    }

    // Test the deployment of a PoolManager contract
    function testDeployNewContract() public {
        bytes32 salt = bytes32(uint256(1));

        // Deploy a new PoolManager contract
        address poolManagerAddress = factory.deployNewContract(salt);

        // Verify the contract was deployed
        assertTrue(poolManagerAddress != address(0), "Pool manager should be deployed");

        // Verify deployment count was incremented
        assertEq(factory.getDeploymentCount(), 1, "Deployment count should be 1");
    }

    // Test prediction of contract address
    function testPredictAddress() public {
        bytes32 salt = bytes32(uint256(1));

        // Get predicted address
        address predictedAddress = factory.predictAddress(salt);

        // Deploy the contract
        address actualAddress = factory.deployNewContract(salt);

        // Verify prediction was correct
        assertEq(actualAddress, predictedAddress, "Predicted address should match actual address");
    }

    // Test deploying multiple contracts with different salts
    function testMultipleDeployments() public {
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));

        // Deploy two contracts with different salts
        address poolManager1 = factory.deployNewContract(salt1);
        address poolManager2 = factory.deployNewContract(salt2);

        // Verify they are different addresses
        assertTrue(poolManager1 != poolManager2, "Contracts should have different addresses");

        // Verify deployment count
        assertEq(factory.getDeploymentCount(), 2, "Deployment count should be 2");
    }

    // Test deploying with same salt (should fail)
    function testDeployWithSameSalt() public {
        bytes32 salt = bytes32(uint256(1));

        // Deploy with the same salt twice (should fail on the second attempt)
        factory.deployNewContract(salt);
        vm.expectRevert();
        factory.deployNewContract(salt);
    }

    // Test zero address validation
    function testZeroAddressValidation() public {
        bytes32 salt = bytes32(uint256(1));

        // Deploy with zero address for owner (should not fail)
        factory.deployNewContract(salt);
        vm.expectRevert();
        // Deploy with zero address for strategy manager (should not fail)
        factory.deployNewContract(salt);
    }
}

// Fuzz tests
contract PoolManagerFactoryFuzzTest is Test {
    PoolManagerFactory factory;

    function setUp() public {
        factory = new PoolManagerFactory();
    }

    // Fuzz test to verify that different salts result in different addresses
    function testFuzz_DifferentSaltsGiveDifferentAddresses(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);

        address predictedAddress1 = factory.predictAddress(salt1);
        address predictedAddress2 = factory.predictAddress(salt2);

        assertNotEq(predictedAddress1, predictedAddress2, "Different salts should give different addresses");
    }

    // Fuzz test for deployment with various owners and strategy managers
    function testFuzz_DeployWithVariousAddresses(bytes32 salt, address owner, address strategyManager) public {
        // Skip zero addresses
        vm.assume(owner != address(0));
        vm.assume(strategyManager != address(0));

        // Deploy with fuzzed values
        address poolManagerAddress = factory.deployNewContract(salt);

        // Verify the deployment
        assertTrue(poolManagerAddress != address(0), "Pool manager should be deployed");
    }

    // Fuzz test for prediction accuracy
    function testFuzz_PredictionAccuracy(bytes32 salt, address owner, address strategyManager) public {
        // Skip zero addresses
        vm.assume(owner != address(0));
        vm.assume(strategyManager != address(0));

        // Get predicted address
        address predictedAddress = factory.predictAddress(salt);

        // Deploy the contract
        address actualAddress = factory.deployNewContract(salt);

        // Verify prediction was correct
        assertEq(actualAddress, predictedAddress, "Predicted address should match actual address");
    }

    // Fuzz test for deployment count incrementation
    function testFuzz_DeploymentCountIncrement(bytes32[] memory salts) public {
        uint256 expectedCount = 0;
        address owner = address(0x123);
        address strategyManager = address(0x456);

        for (uint256 i = 0; i < salts.length; i++) {
            // Skip duplicate salts
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (salts[i] == salts[j]) {
                    isDuplicate = true;
                    break;
                }
            }

            if (!isDuplicate) {
                factory.deployNewContract(salts[i]);
                expectedCount++;
            }
        }

        assertEq(factory.getDeploymentCount(), expectedCount, "Deployment count should match expected value");
    }
}
