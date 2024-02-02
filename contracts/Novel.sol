// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IERC1155NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGnfdAccessControl.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract Novel is ReentrancyGuard, AccessControl, GroupApp {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // greenfield system contracts
    address public constant _CROSS_CHAIN = 0x57b8A375193b2e9c6481f167BaECF1feEf9F7d4B;
    address public constant _GROUP_HUB = 0x0Bf7D3Ed3F777D7fB8D65Fb21ba4FBD9F584B579;
    address public constant _GROUP_TOKEN = 0x089AFF7964E435eB2C7b296B371078B18E2C9A35;
    address public constant _MEMBER_TOKEN = 0x80Dd11998159cbea4BF79650fCc5Da72Ffb51EFc;
    /*----------------- storage -----------------*/
    // owner group ID of novel bucket => NovelInfo
    mapping(uint256 => NovelInfo) public novels;

    // group ID => item price
    mapping(uint256 => uint256) public prices;

    // address => unclaimed amount
    mapping(address => uint256) private _unclaimedFunds;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    struct NovelInfo {
        string name;
        uint256[] chapterGroupIds;
    }

    /*----------------- event/modifier -----------------*/
    event CreateNovelSuccess(address indexed owner, uint256 indexed novelGroupId, string name);
    event List(address indexed owner, uint256 indexed novelGroupId, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);

    modifier onlyGroupOwner(uint256 groupId) {
        require(msg.sender == IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId), "Novel: only group owner");
        _;
    }

    modifier onlyNovelExist(uint256 novelGroupId) {
        require(bytes(novels[novelGroupId].name).length > 0, "Novel: not exists");
        _;
    }

    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public initializer {
        require(_initAdmin != address(0), "Novel: invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, _initAdmin);

        transferGasLimit = 2300;
        fundWallet = _fundWallet;
        feeRate = _feeRate;

        __base_app_init_unchained(_CROSS_CHAIN, _callbackGasLimit, _failureHandleStrategy);
        __group_app_init_unchained(_GROUP_HUB);
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(GroupApp) {
        require(msg.sender == _GROUP_HUB, "Novel: invalid caller");

        if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("Novel: invalid resource type");
        }
    }

    function createNovel(uint256 novelGroupId, string memory name) external onlyGroupOwner(novelGroupId) {
        require(bytes(novels[novelGroupId].name).length == 0, "Novel: already exists");
        require(bytes(name).length > 0, "Novel: empty novel name");
        novels[novelGroupId].name = name;

        emit CreateNovelSuccess(msg.sender, novelGroupId, name);
    }

    function listChapters(uint256 novelGroupId, uint256[] calldata chapterGroupIds, uint256[] calldata priceList) external {
        require(chapterGroupIds.length == priceList.length, "Novel: length mismatch");
        require(chapterGroupIds.length > 0, "Novel: empty list");

        for (uint256 i = 0; i < chapterGroupIds.length; ++i) {
            listChapter(novelGroupId, chapterGroupIds[i], prices[i]);
        }
    }

    function listChapter(uint256 novelGroupId, uint256 chapterGroupId, uint256 price) public onlyNovelExist(novelGroupId) onlyGroupOwner(chapterGroupId) {
        // the owner need to approve the Novel contract to update the group
        require(IGnfdAccessControl(_GROUP_HUB).hasRole(ROLE_UPDATE, msg.sender, address(this)), "Novel: no grant");
        require(prices[chapterGroupId] == 0, "Novel: already listed");
        require(price > 0, "Novel: invalid price");

        novels[novelGroupId].chapterGroupIds.push(chapterGroupId);
        prices[chapterGroupId] = price;
        emit List(msg.sender, novelGroupId, chapterGroupId, price);
    }

    function setPrice(uint256 groupId, uint256 newPrice) external onlyGroupOwner(groupId) {
        require(prices[groupId] > 0, "Novel: not listed");
        require(newPrice > 0, "Novel: invalid price");
        prices[groupId] = newPrice;
        emit PriceUpdated(msg.sender, groupId, newPrice);
    }

    function delist(uint256 novelGroupId, uint256 chapterGroupId) external onlyNovelExist(novelGroupId) onlyGroupOwner(chapterGroupId) {
        require(prices[chapterGroupId] > 0, "Novel: not listed");

        delete prices[chapterGroupId];
        bool chapterDelist = false;
        for (uint256 i = 0; i < novels[novelGroupId].chapterGroupIds.length; ++i) {
            if (novels[novelGroupId].chapterGroupIds[i] == chapterGroupId) {
                novels[novelGroupId].chapterGroupIds[i] = novels[novelGroupId].chapterGroupIds[novels[novelGroupId].chapterGroupIds.length - 1];
                novels[novelGroupId].chapterGroupIds.pop();
                chapterDelist = true;
                break;
            }
        }
        require(chapterDelist, "chapter not found");

        emit Delist(msg.sender, chapterGroupId);
    }

    function buy(uint256 groupId, address refundAddress) external payable {
        uint256 price = prices[groupId];
        require(price > 0, "Novel: not listed");
        require(msg.value >= prices[groupId] + _getTotalFee(), "Novel: insufficient fund");

        _buy(groupId, refundAddress, msg.value - price);
    }

    function buyBatch(uint256[] calldata groupIds, address refundAddress) external payable {
        uint256 receivedValue = msg.value;
        uint256 relayFee = _getTotalFee();
        uint256 amount;
        for (uint256 i; i < groupIds.length; ++i) {
            require(prices[groupIds[i]] > 0, "Novel: not listed");

            amount = prices[groupIds[i]] + relayFee;
            require(receivedValue >= amount, "Novel: insufficient fund");
            receivedValue -= amount;

            _buy(groupIds[i], refundAddress, relayFee);
        }
        if (receivedValue > 0) {
            (bool success,) = payable(refundAddress).call{gas: transferGasLimit, value: receivedValue}("");
            if (!success) {
                _unclaimedFunds[refundAddress] += receivedValue;
            }
        }
    }

    function claim() external nonReentrant {
        uint256 amount = _unclaimedFunds[msg.sender];
        require(amount > 0, "Novel: no unclaimed funds");
        _unclaimedFunds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Novel: claim failed");
    }

    /*----------------- view functions -----------------*/
    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (2, "Novel", "b1e2d2364271044a7d918cbfea985d131c12f0a6");
    }

    function getPrice(uint256 groupId) external view returns (uint256 price) {
        price = prices[groupId];
        require(price > 0, "Novel: not listed");
    }

    function getMinRelayFee() external returns (uint256 amount) {
        amount = _getTotalFee();
    }

    function getUnclaimedAmount() external view returns (uint256 amount) {
        amount = _unclaimedFunds[msg.sender];
    }

    /*----------------- admin functions -----------------*/
    function addOperator(address newOperator) external {
        grantRole(OPERATOR_ROLE, newOperator);
    }

    function removeOperator(address operator) external {
        revokeRole(OPERATOR_ROLE, operator);
    }

    function setFundWallet(address _fundWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fundWallet = _fundWallet;
    }

    function retryPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _retryGroupPackage();
    }

    function skipPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _skipGroupPackage();
    }

    function setFeeRate(uint256 _feeRate) external onlyRole(OPERATOR_ROLE) {
        require(_feeRate < 10_000, "Novel: invalid feeRate");
        feeRate = _feeRate;
    }

    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyRole(OPERATOR_ROLE) {
        _setCallbackGasLimit(_callbackGasLimit);
    }

    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external onlyRole(OPERATOR_ROLE) {
        _setFailureHandleStrategy(_failureHandleStrategy);
    }

    function setTransferGasLimit(uint256 _transferGasLimit) external onlyRole(OPERATOR_ROLE) {
        transferGasLimit = _transferGasLimit;
    }

    /*----------------- internal functions -----------------*/
    function _buy(uint256 groupId, address refundAddress, uint256 amount) internal {
        address buyer = msg.sender;
        require(IERC1155NonTransferable(_MEMBER_TOKEN).balanceOf(buyer, groupId) == 0, "Novel: already purchased");

        address _owner = IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId);
        address[] memory members = new address[](1);
        uint64[] memory expirations = new uint64[](1);
        members[0] = buyer;
        expirations[0] = 0;
        bytes memory callbackData = abi.encode(_owner, buyer, prices[groupId]);
        UpdateGroupSynPackage memory updatePkg = UpdateGroupSynPackage({
            operator: _owner,
            id: groupId,
            opType: UpdateGroupOpType.AddMembers,
            members: members,
            extraData: "",
            memberExpiration: expirations
        });
        ExtraData memory _extraData = ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: callbackData
        });

        IGroupHub(_GROUP_HUB).updateGroup{value: amount}(updatePkg, callbackGasLimit, _extraData);
    }

    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal override {
        if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else {
            revert("Novel: invalid operation type");
        }
    }

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal override {
        (address owner, address buyer, uint256 price) = abi.decode(_callbackData, (address, address, uint256));

        if (_status == STATUS_SUCCESS) {
            uint256 feeRateAmount = (price * feeRate) / 10_000;
            (bool success,) = fundWallet.call{value: feeRateAmount}("");
            require(success, "Novel: transfer fee failed");
            (success,) = owner.call{gas: transferGasLimit, value: price - feeRateAmount}("");
            if (!success) {
                _unclaimedFunds[owner] += price - feeRateAmount;
            }
            emit Buy(buyer, _tokenId);
        } else {
            (bool success,) = buyer.call{gas: transferGasLimit, value: price}("");
            if (!success) {
                _unclaimedFunds[buyer] += price;
            }
            emit BuyFailed(buyer, _tokenId);
        }
    }

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
