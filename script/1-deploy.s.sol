// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import "../contracts/Deployer.sol";
import "../contracts/Novel.sol";

contract DeployScript is Script {
    uint256 public constant callbackGasLimit = 1_000_000; // TODO: TBD
    uint8 public constant failureHandleStrategy = 0; // BlockOnFail
    uint256 public constant tax = 100; // 1%

    address public operator;

    address public crossChain;
    address public groupHub;
    address public initOwner;
    address public fundWallet;

    function setUp() public {
        uint256 privateKey = uint256(vm.envBytes32("OP_PRIVATE_KEY"));
        operator = vm.addr(privateKey);
        console.log("operator balance: %s", operator.balance / 1e18);

        privateKey = uint256(vm.envBytes32("OWNER_PRIVATE_KEY"));
        initOwner = vm.addr(privateKey);
        fundWallet = initOwner;
        console.log("init owner: %s", initOwner);
    }

    function run() public {
        vm.startBroadcast(operator);
        Deployer deployer = new Deployer();
        console.log("deployer address: %s", address(deployer));
        Novel marketplace = new Novel();
        console.log("implNovel address: %s", address(marketplace));

        address proxyAdmin = deployer.calcCreateAddress(address(deployer), uint8(1));
        require(proxyAdmin == deployer.proxyAdmin(), "wrong proxyAdmin address");
        console.log("proxyAdmin address: %s", proxyAdmin);
        address proxyNovel = deployer.calcCreateAddress(address(deployer), uint8(2));
        require(proxyNovel == deployer.proxyNovel(), "wrong proxyNovel address");
        console.log("proxyNovel address: %s", proxyNovel);

        deployer.deploy(address(marketplace), initOwner, fundWallet, tax, callbackGasLimit, failureHandleStrategy);
        vm.stopBroadcast();
    }
}
