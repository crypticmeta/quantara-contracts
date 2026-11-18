// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FEE_BPS_DENOMINATOR} from "./FeeController.sol";
import {SaleKind, SaleOutcome, SaleSetup, SaleSummary, SaleTerms} from "./SaleTypes.sol";

abstract contract Sale is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable creator;
    address public immutable claimManager;
    SaleKind public immutable kind;
    uint256 public immutable inventory;
    uint256 public immutable price;
    uint64 public immutable start;
    uint64 public immutable end;
    uint256 public immutable minContribution;
    uint256 public immutable maxContribution;
    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint16 public immutable feeBps;
    address public immutable feeRecipient;
    uint256 public immutable createdBlock;
    uint256 public immutable projectId;
    uint256 private immutable tokenUnit;

    string public projectName;
    string public description;

    SaleOutcome public outcome;
    uint256 public totalRaised;
    uint256 public totalAllocated;
    uint256 public totalClaimed;
    uint256 public totalRefunded;
    uint256 public serviceFee;
    uint256 public creatorProceeds;
    uint256 public unclaimedParticipants;
    bool public proceedsWithdrawn;
    bool public serviceFeeWithdrawn;
    bool public inventoryWithdrawn;

    mapping(address buyer => uint256 amount) public contributions;
    mapping(address buyer => bool complete) public claimed;
    mapping(address buyer => bool complete) public refunded;

    error InvalidTerms();
    error SaleNotOpen();
    error ContributionTooSmall();
    error WalletLimitExceeded();
    error HardCapExceeded();
    error InventoryExceeded();
    error SaleStillOpen();
    error WrongOutcome();
    error NoEntitlement();
    error TransferFailed();
    error Unauthorized();

    event Contribution(address indexed buyer, uint256 amount, uint256 allocation, uint256 totalRaised);
    event Finalized(SaleOutcome outcome, uint256 totalRaised, uint256 serviceFee, uint256 creatorProceeds);
    event Claimed(address indexed buyer, uint256 amount);
    event Refunded(address indexed buyer, uint256 amount);
    event ProceedsWithdrawn(address indexed creator, uint256 amount);
    event ServiceFeeWithdrawn(address indexed feeRecipient, uint256 amount);
    event InventoryWithdrawn(address indexed creator, uint256 amount);

    constructor(SaleSetup memory setup, SaleTerms memory terms) {
        if (
            terms.start < block.timestamp || terms.end <= terms.start || terms.inventory == 0
                || terms.minContribution == 0 || terms.maxContribution < terms.minContribution
                || terms.hardCap < terms.maxContribution || terms.softCap > terms.hardCap || setup.creator == address(0)
                || setup.feeRecipient == address(0) || setup.feeBps > FEE_BPS_DENOMINATOR
        ) revert InvalidTerms();

        uint256 unit = 10 ** uint256(IERC20Metadata(setup.token).decimals());
        if (terms.kind == SaleKind.FairLaunchProRata) {
            if (terms.price != 0 || Math.mulDiv(terms.minContribution, terms.inventory, terms.hardCap) == 0) {
                revert InvalidTerms();
            }
        } else {
            if (terms.price == 0) revert InvalidTerms();
            uint256 minimumAllocation = Math.mulDiv(terms.minContribution, unit, terms.price);
            if (minimumAllocation == 0 || minimumAllocation > terms.inventory) revert InvalidTerms();
        }

        token = IERC20(setup.token);
        creator = setup.creator;
        claimManager = setup.claimManager;
        feeRecipient = setup.feeRecipient;
        feeBps = setup.feeBps;
        projectName = setup.projectName;
        description = setup.description;
        projectId = setup.projectId;
        createdBlock = block.number;
        tokenUnit = unit;
        kind = terms.kind;
        inventory = terms.inventory;
        price = terms.price;
        start = terms.start;
        end = terms.end;
        minContribution = terms.minContribution;
        maxContribution = terms.maxContribution;
        softCap = terms.softCap;
        hardCap = terms.hardCap;
    }

    function getTerms() external view returns (SaleTerms memory) {
        return SaleTerms(kind, inventory, price, start, end, minContribution, maxContribution, softCap, hardCap);
    }

    function getSummary() external view returns (SaleSummary memory) {
        return SaleSummary(
            address(token),
            creator,
            totalRaised,
            totalAllocated,
            outcome,
            createdBlock,
            feeBps,
            feeRecipient,
            projectName,
            description,
            projectId
        );
    }

    function allocationOf(address buyer) public view returns (uint256) {
        uint256 paid = contributions[buyer];
        if (paid == 0 || outcome == SaleOutcome.Failed) return 0;
        if (kind != SaleKind.FairLaunchProRata) return Math.mulDiv(paid, tokenUnit, price);
        return Math.mulDiv(paid, inventory, totalRaised);
    }

    function previewContribution(uint256 amount) external view returns (uint256) {
        return previewFor(address(0), amount);
    }

    function previewFor(address buyer, uint256 amount) public view returns (uint256) {
        uint256 paid = contributions[buyer];
        if (kind != SaleKind.FairLaunchProRata) {
            return Math.mulDiv(paid + amount, tokenUnit, price) - Math.mulDiv(paid, tokenUnit, price);
        }
        if (totalRaised == 0 && amount == 0) return 0;
        return Math.mulDiv(paid + amount, inventory, totalRaised + amount);
    }

    function contribute() external payable {
        if (outcome != SaleOutcome.Pending || block.timestamp < start || block.timestamp >= end || _soldOut()) {
            revert SaleNotOpen();
        }
        if (msg.value < minContribution) revert ContributionTooSmall();

        uint256 paid = contributions[msg.sender];
        if (paid + msg.value > maxContribution) revert WalletLimitExceeded();
        uint256 raised = totalRaised + msg.value;
        if (raised > hardCap) revert HardCapExceeded();

        uint256 allocation;
        if (kind != SaleKind.FairLaunchProRata) {
            allocation = previewFor(msg.sender, msg.value);
            if (allocation == 0) revert ContributionTooSmall();
            if (allocation > inventory - totalAllocated) revert InventoryExceeded();
            totalAllocated += allocation;
        }

        if (paid == 0) ++unclaimedParticipants;
        contributions[msg.sender] = paid + msg.value;
        totalRaised = raised;
        emit Contribution(msg.sender, msg.value, allocation, raised);
    }

    function finalize() external {
        if (outcome != SaleOutcome.Pending) revert WrongOutcome();
        if (block.timestamp < end && !_soldOut()) revert SaleStillOpen();

        uint256 raised = totalRaised;
        if (raised == 0 || raised < softCap) {
            outcome = SaleOutcome.Failed;
            totalAllocated = 0;
        } else {
            outcome = SaleOutcome.Successful;
            serviceFee = Math.mulDiv(raised, feeBps, FEE_BPS_DENOMINATOR);
            creatorProceeds = raised - serviceFee;
        }
        emit Finalized(outcome, raised, serviceFee, creatorProceeds);
    }

    function claim() external nonReentrant {
        _claim(msg.sender);
    }

    function claimFor(address buyer) external nonReentrant {
        if (msg.sender != claimManager) revert Unauthorized();
        _claim(buyer);
    }

    function refund() external nonReentrant {
        _refund(msg.sender, payable(msg.sender));
    }

    function refundFor(address buyer) external nonReentrant {
        if (msg.sender != claimManager) revert Unauthorized();
        _refund(buyer, payable(buyer));
    }

    function refundTo(address payable recipient) external nonReentrant {
        if (recipient == address(0)) revert Unauthorized();
        _refund(msg.sender, recipient);
    }

    function withdrawProceeds() external nonReentrant {
        if (msg.sender != creator) revert Unauthorized();
        if (outcome != SaleOutcome.Successful) revert WrongOutcome();
        if (proceedsWithdrawn || creatorProceeds == 0) revert NoEntitlement();
        proceedsWithdrawn = true;
        _sendNative(payable(creator), creatorProceeds);
        emit ProceedsWithdrawn(creator, creatorProceeds);
    }

    function withdrawServiceFee() external nonReentrant {
        if (outcome != SaleOutcome.Successful) revert WrongOutcome();
        if (serviceFeeWithdrawn || serviceFee == 0) revert NoEntitlement();
        serviceFeeWithdrawn = true;
        _sendNative(payable(feeRecipient), serviceFee);
        emit ServiceFeeWithdrawn(feeRecipient, serviceFee);
    }

    function withdrawInventory() external nonReentrant {
        if (msg.sender != creator) revert Unauthorized();
        if (outcome == SaleOutcome.Pending) revert WrongOutcome();
        if (inventoryWithdrawn) revert NoEntitlement();

        uint256 available = inventory;
        if (outcome == SaleOutcome.Successful) {
            if (kind == SaleKind.FairLaunchProRata && unclaimedParticipants != 0) revert NoEntitlement();
            available -= totalAllocated;
        }
        if (available == 0) revert NoEntitlement();
        inventoryWithdrawn = true;
        token.safeTransfer(creator, available);
        emit InventoryWithdrawn(creator, available);
    }

    function _claim(address buyer) private {
        if (outcome != SaleOutcome.Successful) revert WrongOutcome();
        if (contributions[buyer] == 0 || claimed[buyer]) revert NoEntitlement();

        uint256 allocation = allocationOf(buyer);
        claimed[buyer] = true;
        --unclaimedParticipants;
        totalClaimed += allocation;
        if (kind == SaleKind.FairLaunchProRata) totalAllocated += allocation;
        if (allocation != 0) token.safeTransfer(buyer, allocation);
        emit Claimed(buyer, allocation);
    }

    function _refund(address buyer, address payable recipient) private {
        if (outcome != SaleOutcome.Failed) revert WrongOutcome();
        uint256 amount = contributions[buyer];
        if (amount == 0 || refunded[buyer]) revert NoEntitlement();

        refunded[buyer] = true;
        totalRefunded += amount;
        _sendNative(recipient, amount);
        emit Refunded(buyer, amount);
    }

    function _soldOut() private view returns (bool) {
        return totalRaised == hardCap || (kind != SaleKind.FairLaunchProRata && totalAllocated == inventory);
    }

    function _sendNative(address payable recipient, uint256 amount) private {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
