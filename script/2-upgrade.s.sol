// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../contracts/interface/INovel.sol";
import "../contracts/Novel.sol";

contract UpgradeScript is Script {
    address public operator;

    address public crossChain;
    address public groupHub;
    address public owner;
    address public fundWallet;

    address public proxyAdmin;
    address public proxyMarketPlace;
    address public oldImplMarketPlace;

    function setUp() public {
        uint256 privateKey = uint256(vm.envBytes32("OWNER_PRIVATE_KEY"));
        owner = vm.addr(privateKey);
        console.log("init owner: %s", owner);

        proxyAdmin = vm.envAddress("PROXY_ADMIN");
        console.log("proxyAdmin address: %s", proxyAdmin);

        proxyMarketPlace = vm.envAddress("PROXY_MP");
        console.log("proxyMarketPlace address: %s", proxyMarketPlace);

        oldImplMarketPlace = vm.envAddress("IMPL_MP");
        console.log("oldImplMarketPlace address: %s", oldImplMarketPlace);
    }

    function run() public {
        vm.startBroadcast(owner);
        Novel newImpl = new Novel();
        require(address(newImpl) != oldImplMarketPlace, "same impl address");

        (uint256 oldVersion,,) = INovel(proxyMarketPlace).versionInfo();
        (uint256 newVersion,,) = newImpl.versionInfo();
        require(oldVersion < newVersion, "new version must be greater than old version");
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(proxyMarketPlace), address(newImpl));
        vm.stopBroadcast();

        console.log("new implMarketPlace address: %s", address(newImpl));
    }
}
