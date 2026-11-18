// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";
import {TokenFactory} from "../src/TokenFactory.sol";
import {ClaimManager, IClaimableSale} from "../src/ClaimManager.sol";
import {Sale} from "../src/Sale.sol";
import {SaleKind, SaleOutcome, SaleTerms} from "../src/SaleTypes.sol";

interface Vm {
    function deal(address who, uint256 balance) external;
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
    function expectRevert(bytes4 selector) external;
    function expectRevert() external;
}

contract RejectNative {
    receive() external payable {
        revert();
    }
}

contract LaunchpadTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant FOUNDER = address(0xf001);
    address private constant BUYER_A = address(0xb001);
    address private constant BUYER_B = address(0xb002);
    address private constant FEE_RECIPIENT = address(0xfe01);

    LaunchFactory private factory;

    function setUp() public {
        factory = new LaunchFactory(FEE_RECIPIENT, 100);
        vm.deal(BUYER_A, 100 ether);
        vm.deal(BUYER_B, 100 ether);
        vm.warp(100);
    }

    function testPublicFactoriesProjectScopeAndAtomicFunding() public {
        vm.prank(FOUNDER);
        uint256 projectId = factory.registerProject("Launch", "Public example");
        vm.prank(FOUNDER);
        uint256 sameProjectId = factory.registerProject("Launch", "Public example");
        vm.prank(BUYER_A);
        uint256 otherWalletProjectId = factory.registerProject("Launch", "Public example");
        assert(projectId == sameProjectId && sameProjectId == otherWalletProjectId);
        assert(factory.projectCount(FOUNDER) == 1 && factory.projectCount(BUYER_A) == 1);

        IERC20Metadata token = _createToken(FOUNDER, 6, 1_000_000_000);
        SaleTerms memory terms = _terms(SaleKind.FixedPrice, 50_000_000);
        vm.expectRevert();
        vm.prank(FOUNDER);
        factory.createSale(address(token), terms, "Launch", "Public example");
        assert(factory.saleCount() == 0);

        Sale sale = _createSale(FOUNDER, token, terms);
        assert(sale.creator() == FOUNDER && sale.projectId() == projectId);
        assert(factory.isSale(address(sale)) && factory.saleAt(0) == address(sale));
        assert(factory.ownerSaleCount(FOUNDER) == 1 && factory.ownerSaleCount(BUYER_A) == 0);
        assert(factory.ownerSaleAt(FOUNDER, 0) == address(sale) && factory.projectCount(FOUNDER) == 1);
        assert(token.decimals() == 6 && token.totalSupply() == 1_000_000_000);
        assert(token.balanceOf(address(sale)) == terms.inventory);
        assert(token.balanceOf(FOUNDER) == token.totalSupply() - terms.inventory);

        IERC20Metadata secondToken = _createToken(BUYER_A, 0, 100);
        Sale otherSale = _createSale(BUYER_A, secondToken, _terms(SaleKind.FixedPrice, 50));
        assert(otherSale.creator() == BUYER_A && factory.ownerSaleAt(BUYER_A, 0) == address(otherSale));
        assert(factory.saleAt(1) == address(otherSale));
    }

    function testTokenFactoryChecksExactAllocationAndSumsBalances() public {
        address[] memory recipients = new address[](2);
        recipients[0] = FOUNDER;
        recipients[1] = BUYER_A;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 70;
        amounts[1] = 30;

        TokenFactory tokens = factory.tokenFactory();
        vm.expectRevert(TokenFactory.InvalidAllocation.selector);
        vm.prank(FOUNDER);
        tokens.createToken("Launch", "QX", 0, 101, recipients, amounts);

        vm.prank(FOUNDER);
        IERC20 token = IERC20(tokens.createToken("Launch", "QX", 0, 100, recipients, amounts));
        assert(token.totalSupply() == 100 && token.balanceOf(FOUNDER) == 70 && token.balanceOf(BUYER_A) == 30);
    }

    function testFixedPriceSettlementFeeInventoryAndOneTimeClaims() public {
        IERC20Metadata token = _createToken(FOUNDER, 6, 1_000_000_000);
        SaleTerms memory terms = _terms(SaleKind.FixedPrice, 20_000_000);
        terms.price = 0.3 ether;
        terms.minContribution = 0.1 ether;
        Sale sale = _createSale(FOUNDER, token, terms);

        vm.expectRevert(Sale.SaleNotOpen.selector);
        vm.prank(BUYER_A);
        sale.contribute{value: 0.5 ether}();
        vm.warp(terms.start);

        _contribute(sale, BUYER_A, 0.5 ether);
        uint256 secondAllocation = sale.previewFor(BUYER_A, 0.4 ether);
        assert(secondAllocation == 1_333_334);
        _contribute(sale, BUYER_A, 0.4 ether);
        _contribute(sale, BUYER_B, 1 ether);
        assert(sale.totalRaised() == 1.9 ether && sale.totalAllocated() == 6_333_333);
        assert(sale.allocationOf(BUYER_A) == 3_000_000 && sale.allocationOf(BUYER_B) == 3_333_333);

        vm.expectRevert(Sale.SaleStillOpen.selector);
        sale.finalize();
        vm.warp(terms.end);
        vm.prank(BUYER_B);
        sale.finalize();

        assert(sale.outcome() == SaleOutcome.Successful);
        assert(sale.serviceFee() == 0.019 ether && sale.creatorProceeds() == 1.881 ether);
        vm.expectRevert(Sale.Unauthorized.selector);
        vm.prank(BUYER_A);
        sale.withdrawProceeds();
        vm.expectRevert(Sale.Unauthorized.selector);
        vm.prank(BUYER_A);
        sale.withdrawInventory();

        vm.prank(FOUNDER);
        sale.withdrawInventory();
        assert(token.balanceOf(address(sale)) == 6_333_333);

        vm.prank(BUYER_A);
        sale.claim();
        ClaimManager manager = factory.claimManager();
        vm.prank(BUYER_B);
        manager.claim(IClaimableSale(address(sale)));
        assert(sale.claimed(BUYER_A) && sale.claimed(BUYER_B));
        assert(token.balanceOf(BUYER_A) == 3_000_000 && token.balanceOf(BUYER_B) == 3_333_333);
        assert(sale.totalClaimed() == 6_333_333 && token.balanceOf(address(sale)) == 0);

        vm.expectRevert(Sale.NoEntitlement.selector);
        vm.prank(BUYER_A);
        sale.claim();
        vm.prank(FOUNDER);
        sale.withdrawProceeds();
        sale.withdrawServiceFee();
        assert(FOUNDER.balance == 1.881 ether && FEE_RECIPIENT.balance == 0.019 ether);
        assert(address(sale).balance == 0);
    }

    function testFixedPriceContributionWalletAndInventoryLimits() public {
        SaleTerms memory terms = _terms(SaleKind.FixedPrice, 3_500_000);
        terms.minContribution = 1 ether;
        terms.maxContribution = 3 ether;
        Sale sale = _createSale(FOUNDER, _createToken(FOUNDER, 6, 10_000_000), terms);
        vm.warp(terms.start);

        vm.expectRevert(Sale.ContributionTooSmall.selector);
        vm.prank(BUYER_A);
        sale.contribute{value: 0.5 ether}();
        _contribute(sale, BUYER_A, 3 ether);

        vm.expectRevert(Sale.WalletLimitExceeded.selector);
        vm.prank(BUYER_A);
        sale.contribute{value: 1 ether}();
        vm.expectRevert(Sale.InventoryExceeded.selector);
        vm.prank(BUYER_B);
        sale.contribute{value: 1 ether}();

        assert(sale.totalRaised() == 3 ether && sale.totalAllocated() == 3_000_000);
        vm.warp(terms.end);
        vm.expectRevert(Sale.SaleNotOpen.selector);
        vm.prank(BUYER_B);
        sale.contribute{value: 1 ether}();
    }

    function testFairLaunchFCFSFinalizesWhenInventorySellsOut() public {
        SaleTerms memory terms = _terms(SaleKind.FairLaunchFCFS, 3_000_000);
        terms.softCap = 2 ether;
        IERC20Metadata token = _createToken(FOUNDER, 6, 10_000_000);
        Sale sale = _createSale(FOUNDER, token, terms);

        vm.warp(terms.start);
        _contribute(sale, BUYER_A, 1 ether);
        _contribute(sale, BUYER_B, 2 ether);
        sale.finalize();
        assert(sale.outcome() == SaleOutcome.Successful);

        vm.prank(BUYER_A);
        sale.claim();
        vm.prank(BUYER_B);
        sale.claim();
        assert(token.balanceOf(BUYER_A) == 1_000_000 && token.balanceOf(BUYER_B) == 2_000_000);
    }

    function testRefundFailureRollsBackThenAllowsAlternateRecipient() public {
        address rejectBuyer = address(new RejectNative());
        vm.deal(rejectBuyer, 10 ether);
        SaleTerms memory terms = _terms(SaleKind.FairLaunchFCFS, 30_000_000);
        terms.softCap = 10 ether;
        IERC20Metadata token = _createToken(FOUNDER, 6, 100_000_000);
        Sale sale = _createSale(FOUNDER, token, terms);
        vm.warp(terms.start);
        _contribute(sale, rejectBuyer, 2 ether);
        _contribute(sale, BUYER_A, 1 ether);
        vm.warp(terms.end);
        sale.finalize();
        assert(sale.outcome() == SaleOutcome.Failed && sale.totalAllocated() == 0);

        vm.expectRevert(Sale.TransferFailed.selector);
        vm.prank(rejectBuyer);
        sale.refund();
        assert(!sale.refunded(rejectBuyer) && sale.totalRefunded() == 0 && address(sale).balance == 3 ether);

        vm.expectRevert(Sale.Unauthorized.selector);
        vm.prank(BUYER_B);
        sale.refundFor(rejectBuyer);

        vm.prank(rejectBuyer);
        sale.refundTo(payable(BUYER_B));
        ClaimManager manager = factory.claimManager();
        vm.prank(BUYER_A);
        manager.refund(IClaimableSale(address(sale)));
        assert(sale.refunded(rejectBuyer) && sale.refunded(BUYER_A));
        assert(sale.totalRefunded() == sale.totalRaised() && address(sale).balance == 0);

        vm.expectRevert(Sale.NoEntitlement.selector);
        vm.prank(rejectBuyer);
        sale.refundTo(payable(BUYER_B));
        vm.expectRevert(Sale.WrongOutcome.selector);
        vm.prank(BUYER_A);
        sale.claim();
        vm.expectRevert(Sale.WrongOutcome.selector);
        vm.prank(FOUNDER);
        sale.withdrawProceeds();
        vm.prank(FOUNDER);
        sale.withdrawInventory();
        assert(token.balanceOf(FOUNDER) == token.totalSupply());
    }

    function testProRataFairLaunchHardCapAndResidualInventory() public {
        SaleTerms memory terms = _terms(SaleKind.FairLaunchProRata, 10);
        terms.minContribution = 1;
        terms.maxContribution = 5;
        terms.softCap = 2;
        terms.hardCap = 6;
        IERC20Metadata token = _createToken(FOUNDER, 0, 50);
        Sale sale = _createSale(FOUNDER, token, terms);

        vm.warp(terms.start);
        _contribute(sale, BUYER_A, 1);
        _contribute(sale, BUYER_B, 2);
        vm.expectRevert(Sale.HardCapExceeded.selector);
        vm.prank(BUYER_A);
        sale.contribute{value: 4}();
        assert(sale.previewFor(BUYER_A, 0) == 3 && sale.allocationOf(BUYER_B) == 6);
        vm.warp(terms.end);
        sale.finalize();

        vm.expectRevert(Sale.NoEntitlement.selector);
        vm.prank(FOUNDER);
        sale.withdrawInventory();
        vm.prank(BUYER_A);
        sale.claim();
        vm.prank(BUYER_B);
        sale.claim();
        assert(sale.unclaimedParticipants() == 0 && sale.totalAllocated() == 9);
        assert(token.balanceOf(BUYER_A) == 3 && token.balanceOf(BUYER_B) == 6);
        vm.prank(FOUNDER);
        sale.withdrawInventory();
        assert(token.balanceOf(FOUNDER) == 41 && token.balanceOf(address(sale)) == 0);
    }

    function testFeeReceiverFailureDoesNotBlockFounderAndAmountsStayClaimable() public {
        factory = new LaunchFactory(address(new RejectNative()), 200);
        SaleTerms memory terms = _terms(SaleKind.FixedPrice, 10_000_000);
        Sale sale = _createSale(FOUNDER, _createToken(FOUNDER, 6, 100_000_000), terms);
        vm.warp(terms.start);
        _contribute(sale, BUYER_A, 10 ether);
        sale.finalize();

        vm.expectRevert(Sale.TransferFailed.selector);
        sale.withdrawServiceFee();
        assert(!sale.serviceFeeWithdrawn());
        vm.prank(FOUNDER);
        sale.withdrawProceeds();
        assert(FOUNDER.balance == 9.8 ether && address(sale).balance == 0.2 ether);

        vm.prank(BUYER_A);
        sale.claim();
        assert(sale.claimed(BUYER_A));
    }

    function testRejectsTermsWithZeroAllocationAtPublishedMinimum() public {
        IERC20Metadata token = _createToken(FOUNDER, 0, 50);
        SaleTerms memory terms = _terms(SaleKind.FixedPrice, 20);
        terms.minContribution = 0.1 ether;
        vm.expectRevert(Sale.InvalidTerms.selector);
        vm.prank(FOUNDER);
        factory.createSale(address(token), terms, "Launch", "Public example");

        SaleTerms memory proRata = _terms(SaleKind.FairLaunchProRata, 2);
        proRata.minContribution = 1;
        proRata.maxContribution = 3;
        proRata.hardCap = 4;
        vm.expectRevert(Sale.InvalidTerms.selector);
        vm.prank(FOUNDER);
        factory.createSale(address(token), proRata, "Launch", "Public example");
    }

    function testFuzzProRataConservesFundsAndInventory(uint64 first, uint64 second, uint96 extra) public {
        uint256 paidByA = uint256(first) + 1;
        uint256 paidByB = uint256(second) + 1;
        uint256 total = paidByA + paidByB;
        uint256 inventory = total + uint256(extra);
        IERC20Metadata token = _createToken(FOUNDER, 0, inventory);
        SaleTerms memory terms = _terms(SaleKind.FairLaunchProRata, inventory);
        terms.minContribution = 1;
        terms.maxContribution = total;
        terms.hardCap = total;
        terms.softCap = 1;
        terms.price = 0;
        Sale sale = _createSale(FOUNDER, token, terms);
        vm.warp(terms.start);
        _contribute(sale, BUYER_A, paidByA);
        _contribute(sale, BUYER_B, paidByB);
        sale.finalize();

        vm.prank(BUYER_A);
        sale.claim();
        vm.prank(BUYER_B);
        sale.claim();
        assert(sale.totalAllocated() == sale.totalClaimed());
        assert(sale.totalClaimed() <= inventory && sale.totalClaimed() + 1 >= inventory);
        assert(sale.creatorProceeds() + sale.serviceFee() == total);
        assert(token.balanceOf(BUYER_A) + token.balanceOf(BUYER_B) + token.balanceOf(address(sale)) == inventory);
    }

    function _createToken(address owner, uint8 decimals, uint256 supply) private returns (IERC20Metadata) {
        address[] memory recipients = new address[](1);
        recipients[0] = owner;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = supply;
        TokenFactory tokens = factory.tokenFactory();
        vm.prank(owner);
        return IERC20Metadata(tokens.createToken("Launch", "QX", decimals, supply, recipients, amounts));
    }

    function _createSale(address owner, IERC20Metadata token, SaleTerms memory terms) private returns (Sale) {
        vm.prank(owner);
        token.approve(address(factory), terms.inventory);
        vm.prank(owner);
        return Sale(factory.createSale(address(token), terms, "Launch", "Public example"));
    }

    function _terms(SaleKind kind, uint256 inventory) private view returns (SaleTerms memory) {
        return SaleTerms({
            kind: kind,
            inventory: inventory,
            price: kind == SaleKind.FairLaunchProRata ? 0 : 1 ether,
            start: uint64(block.timestamp + 10),
            end: uint64(block.timestamp + 60),
            minContribution: 1 ether,
            maxContribution: 20 ether,
            softCap: 0,
            hardCap: 50 ether
        });
    }

    function _contribute(Sale sale, address buyer, uint256 amount) private {
        vm.prank(buyer);
        sale.contribute{value: amount}();
    }
}
