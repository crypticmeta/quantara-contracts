// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenFactory} from "./TokenFactory.sol";
import {FeeController} from "./FeeController.sol";
import {ClaimManager} from "./ClaimManager.sol";
import {FixedPriceSale} from "./FixedPriceSale.sol";
import {FairLaunchDeployer} from "./FairLaunchDeployer.sol";
import {SaleKind, SaleSetup, SaleTerms} from "./SaleTypes.sol";

contract LaunchFactory {
    using SafeERC20 for IERC20;

    struct Project {
        string name;
        string description;
    }

    TokenFactory public immutable tokenFactory;
    FeeController public immutable feeController;
    ClaimManager public immutable claimManager;
    FairLaunchDeployer public immutable fairLaunchDeployer;

    address[] private sales;
    mapping(address creator => address[]) private ownerSales;
    mapping(address sale => bool known) public isSale;
    mapping(address creator => Project[]) private projects;
    mapping(address creator => mapping(bytes32 key => uint256 indexPlusOne)) private projectIndexes;

    error InvalidProject();
    error UnknownToken();

    event ProjectRegistered(address indexed creator, uint256 indexed projectId, string name, string description);
    event SaleCreated(
        address indexed creator,
        address indexed sale,
        address indexed token,
        SaleKind kind,
        string projectName,
        string description
    );

    constructor(address feeRecipient, uint16 feeBps) {
        tokenFactory = new TokenFactory();
        feeController = new FeeController(feeRecipient, feeBps);
        claimManager = new ClaimManager();
        fairLaunchDeployer = new FairLaunchDeployer();
    }

    function registerProject(string calldata name, string calldata description) external returns (uint256 projectId) {
        return _registerProject(name, description);
    }

    function projectCount(address owner) external view returns (uint256) {
        return projects[owner].length;
    }

    function projectAt(address owner, uint256 index) external view returns (Project memory) {
        return projects[owner][index];
    }

    function saleCount() external view returns (uint256) {
        return sales.length;
    }

    function saleAt(uint256 index) external view returns (address) {
        return sales[index];
    }

    function ownerSaleCount(address owner) external view returns (uint256) {
        return ownerSales[owner].length;
    }

    function ownerSaleAt(address owner, uint256 index) external view returns (address) {
        return ownerSales[owner][index];
    }

    function createSale(
        address token,
        SaleTerms calldata terms,
        string calldata projectName,
        string calldata description
    ) external returns (address sale) {
        if (!tokenFactory.isToken(token)) revert UnknownToken();

        SaleSetup memory setup = SaleSetup(
            token,
            msg.sender,
            address(claimManager),
            feeController.feeBps(),
            feeController.feeRecipient(),
            _registerProject(projectName, description),
            projectName,
            description
        );
        if (terms.kind == SaleKind.FixedPrice) {
            sale = address(new FixedPriceSale(setup, terms));
        } else {
            sale = fairLaunchDeployer.deploy(setup, terms);
        }

        IERC20(token).safeTransferFrom(msg.sender, sale, terms.inventory);
        sales.push(sale);
        ownerSales[msg.sender].push(sale);
        isSale[sale] = true;
        emit SaleCreated(msg.sender, sale, token, terms.kind, projectName, description);
    }

    function _registerProject(string calldata name, string calldata description) private returns (uint256 projectId) {
        if (bytes(name).length == 0 || bytes(name).length > 100 || bytes(description).length > 800) {
            revert InvalidProject();
        }

        bytes32 key = keccak256(abi.encode(name, description));
        uint256 existing = projectIndexes[msg.sender][key];
        if (existing != 0) return existing - 1;

        Project[] storage ownerProjects = projects[msg.sender];
        projectId = ownerProjects.length;
        ownerProjects.push(Project(name, description));
        projectIndexes[msg.sender][key] = projectId + 1;
        emit ProjectRegistered(msg.sender, projectId, name, description);
    }
}
