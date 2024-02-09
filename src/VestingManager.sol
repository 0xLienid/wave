// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract VestingManager {
    // ------ ERRORS ------ //

    error NotOnwer();
    error NotPoolOwner();
    error MissingFee();
    error LengthMismatch();
    error VestingNotStarted();
    error BeforeCliff();
    error NoClaim();
    error InsufficientApproval();
    error InsufficientAllocation();

    // ------ EVENTS ------ //

    enum VestType {LINEAR, NONLINEAR}

    event LinearVestCreated(
        uint256 indexed claimId,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint48 vestingStart,
        uint48 cliffPeriod,
        uint48 vestingPeriod
    );

    event NonLinearVestCreated(
        uint256 indexed claimId,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint48 vestingStart,
        uint256[] vestingPercents,
        uint48[] vestingPeriods
    );

    event TokenGenerationEvent(uint256 indexed claimId, address indexed token, uint256 amount);

    event VestingPoolIncreased(uint256 indexed claimId, uint256 amount);

    event Claimed(uint256 indexed claimId, address indexed claimer, uint256 amount);

    // ------ DATA STRUCTURES ------ //

    struct Claim {
        uint256 allocation;
        uint256 claimed;
    }

    struct LinearVest {
        address owner;
        address token;
        uint256 amount;
        uint48 vestingStart;
        uint48 cliffPeriod;
        uint48 vestingPeriod;
    }

    struct NonLinearVest {
        address owner;
        address token;
        uint256 amount;
        uint256[] vestingPercents;
        uint48 vestingStart;
        uint48[] vestingPeriods;
    }

    // ------ STATE VARIABLES ------ //

    address public owner;

    uint256 public fee; // out of 1_000_000

    LinearVest[] public linearVests;
    NonLinearVest[] public nonLinearVests;

    mapping(uint256 => mapping(address => Claim)) public linearClaims;
    mapping(uint256 => mapping(address => Claim)) public nonLinearClaims;

    mapping(uint256 => mapping(address => mapping(address => uint256))) public linearApprovals;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public nonLinearApprovals;

    constructor(uint256 fee_) {
        owner = msg.sender;
        fee = fee_;
    }

    // ------ MODIFIERS ------ //

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOnwer();
        _;
    }

    // ------ TOKEN POOL MANAGEMENT ------ //

    function createLinearVestingPool(
        address[] calldata claimers_,
        uint256[] calldata allocations_,
        uint48 cliffPeriod_,
        uint48 vestingPeriod_
    ) external payable returns (uint256) {
        if (msg.value != fee) revert MissingFee();
        if (claimers_.length != allocations_.length) revert LengthMismatch();

        uint256 id = linearVests.length;

        // Create Claims object
        uint256 numClaims = claimers_.length;
        for (uint256 i; i < numClaims;) {
            linearClaims[id][claimers_[i]] = Claim({allocation: allocations_[i], claimed: 0});
            unchecked {
                ++i;
            }
        }

        linearVests.push(
            LinearVest({
                owner: msg.sender,
                token: address(0),
                amount: 0,
                vestingStart: 0,
                cliffPeriod: cliffPeriod_,
                vestingPeriod: vestingPeriod_
            })
        );

        emit LinearVestCreated(
            id,
            msg.sender,
            address(0),
            0,
            0,
            cliffPeriod_,
            vestingPeriod_
        );

        return id;
    }

    function createNonLinearVestingPool(
        address[] calldata claimers_,
        uint256[] calldata allocations_,
        uint48[] calldata vestingPeriods_,
        uint256[] calldata vestingPercents_
    ) external payable returns (uint256) {
        if (msg.value != fee) revert MissingFee();
        if (claimers_.length != allocations_.length) revert LengthMismatch();
        if (vestingPeriods_.length != vestingPercents_.length) revert LengthMismatch();

        uint256 id = nonLinearVests.length;

        // Create Claims object
        uint256 numClaims = claimers_.length;
        for (uint256 i; i < numClaims;) {
            nonLinearClaims[id][claimers_[i]] = Claim({allocation: allocations_[i], claimed: 0});
            unchecked {
                ++i;
            }
        }

        nonLinearVests.push(
            NonLinearVest({
                owner: msg.sender,
                token: address(0),
                amount: 0,
                vestingPercents: vestingPercents_,
                vestingStart: 0,
                vestingPeriods: vestingPeriods_
            })
        );

        emit NonLinearVestCreated(
            id,
            msg.sender,
            address(0),
            0,
            0,
            vestingPercents_,
            vestingPeriods_
        );

        return id;
    }

    function addClaimers(VestType type_, uint256 id_, address[] calldata claimers_, uint256[] calldata allocations_) external payable {
        if (msg.value != fee) revert MissingFee();
        if (claimers_.length != allocations_.length) revert LengthMismatch();

        if (type_ == VestType.LINEAR) {
            LinearVest storage vest = linearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            uint256 numClaims = claimers_.length;
            for (uint256 i; i < numClaims;) {
                linearClaims[id_][claimers_[i]] = Claim({allocation: allocations_[i], claimed: 0});
                unchecked {
                    ++i;
                }
            }
        } else {
            NonLinearVest storage vest = nonLinearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            uint256 numClaims = claimers_.length;
            for (uint256 i; i < numClaims;) {
                nonLinearClaims[id_][claimers_[i]] = Claim({allocation: allocations_[i], claimed: 0});
                unchecked {
                    ++i;
                }
            }
        }
    }

    function tokenGenerationEvent(VestType type_, uint256 id_, address token_, uint256 amount_) external {
        if (type_ == VestType.LINEAR) {
            LinearVest storage vest = linearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            vest.token = token_;
            vest.amount = amount_;
            vest.vestingStart = uint48(block.timestamp);
        } else {
            NonLinearVest storage vest = nonLinearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            vest.token = token_;
            vest.amount = amount_;
            vest.vestingStart = uint48(block.timestamp);
        }

        ERC20(token_).transferFrom(msg.sender, address(this), amount_);

        emit TokenGenerationEvent(id_, token_, amount_);
    }

    function increaseVestingPool(VestType type_, uint256 id_, uint256 amount_) external {
        address vestToken;

        if (type_ == VestType.LINEAR) {
            LinearVest storage vest = linearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            vestToken = vest.token;
            vest.amount += amount_;
        } else {
            NonLinearVest storage vest = nonLinearVests[id_];
            if (msg.sender != vest.owner) revert NotPoolOwner();

            vestToken = vest.token;
            vest.amount += amount_;
        }

        ERC20(vestToken).transferFrom(msg.sender, address(this), amount_);

        emit VestingPoolIncreased(id_, amount_);
    }

    // ------ POSITION MANAGEMENT ------ //

    function claim(VestType type_, uint256 id_) external {
        uint256 claimableAmount;

        if (type_ == VestType.LINEAR) {
            LinearVest storage vest = linearVests[id_];

            if (vest.vestingStart == 0) revert VestingNotStarted();
            if (block.timestamp < vest.vestingStart + vest.cliffPeriod) revert BeforeCliff();

            // Find user's claim
            Claim storage userClaim = linearClaims[id_][msg.sender];

            if (userClaim.allocation == 0) revert NoClaim();

            uint256 claimable = (block.timestamp - vest.vestingStart) * userClaim.allocation / vest.vestingPeriod; // Linear vesting
            claimableAmount = claimable - userClaim.claimed; // Will revert if claimableAmount < amount_
            
            if (claimableAmount > 0) {
                userClaim.claimed += claimableAmount;
                ERC20(vest.token).transfer(msg.sender, claimableAmount);
            }
        } else {
            NonLinearVest storage vest = nonLinearVests[id_];

            if (vest.vestingStart == 0) revert VestingNotStarted();
            if (block.timestamp < vest.vestingStart + vest.vestingPeriods[0]) revert BeforeCliff();

            // Find user's claim
            Claim storage userClaim = nonLinearClaims[id_][msg.sender];

            if (userClaim.allocation == 0) revert NoClaim();

            // Find the cumulative percentage vest
            uint256 cumulativePeriod;
            uint256 cumulativePercentage;
            uint256 numPeriods = vest.vestingPeriods.length;
            for (uint256 i; i < numPeriods;) {
                if (block.timestamp < vest.vestingStart + cumulativePeriod + vest.vestingPeriods[i]) {
                    cumulativePeriod += vest.vestingPeriods[i];
                    cumulativePercentage += vest.vestingPercents[i];
                }
                unchecked {
                    ++i;
                }
            }

            uint256 claimable = userClaim.allocation * cumulativePercentage / 1_000_000; // Non-linear vesting
            claimableAmount = claimable - userClaim.claimed; // Will revert if claimableAmount < amount_

            if (claimableAmount > 0) {
                userClaim.claimed += claimableAmount;
                ERC20(vest.token).transfer(msg.sender, claimableAmount);
            }
        }

        emit Claimed(id_, msg.sender, claimableAmount);
    }

    function approve(VestType type_, uint256 id_, address spender_, uint256 amount_) external {
        if (type_ == VestType.LINEAR) {
            // Get user's claim
            Claim memory userClaim = linearClaims[id_][msg.sender];
            if (userClaim.allocation == 0) revert NoClaim();

            linearApprovals[id_][msg.sender][spender_] = amount_;
        } else {
            // Get user's claim
            Claim memory userClaim = nonLinearClaims[id_][msg.sender];
            if (userClaim.allocation == 0) revert NoClaim();

            nonLinearApprovals[id_][msg.sender][spender_] = amount_;
        }
    }

    function transfer(VestType type_, uint256 id_, address to_, uint256 amount_) external {
        if (type_ == VestType.LINEAR) {
            // Get user's claim
            Claim storage userClaim = linearClaims[id_][msg.sender];

            if (userClaim.allocation == 0) revert NoClaim();
            if (amount_ > userClaim.allocation - userClaim.claimed) revert InsufficientAllocation();

            userClaim.allocation -= amount_;
            linearClaims[id_][to_].allocation += amount_;
        } else {
            // Get user's claim
            Claim storage userClaim = nonLinearClaims[id_][msg.sender];

            if (userClaim.allocation == 0) revert NoClaim();
            if (amount_ > userClaim.allocation - userClaim.claimed) revert InsufficientAllocation();

            userClaim.allocation -= amount_;
            nonLinearClaims[id_][to_].allocation += amount_;
        }
    }

    function transferFrom(VestType type_, uint256 id_, address from_, address to_, uint256 amount_) external {
        if (type_ == VestType.LINEAR) {
            // Get user's claim
            Claim storage userClaim = linearClaims[id_][from_];

            if (userClaim.allocation == 0) revert NoClaim();
            if (amount_ > userClaim.allocation - userClaim.claimed) revert InsufficientAllocation();
            if (amount_ > linearApprovals[id_][from_][msg.sender]) revert InsufficientApproval();

            userClaim.allocation -= amount_;
            linearClaims[id_][to_].allocation += amount_;
        } else {
            // Get user's claim
            Claim storage userClaim = nonLinearClaims[id_][from_];

            if (userClaim.allocation == 0) revert NoClaim();
            if (amount_ > userClaim.allocation - userClaim.claimed) revert InsufficientAllocation();
            if (amount_ > nonLinearApprovals[id_][from_][msg.sender]) revert InsufficientApproval();

            userClaim.allocation -= amount_;
            nonLinearClaims[id_][to_].allocation += amount_;
        }
    }

    // ------ OWNER MANAGEMENT ------ //

    function setOwner(address newOwner_) external onlyOwner {
        owner = newOwner_;
    }

    function setFee(uint256 newFee_) external onlyOwner {
        fee = newFee_;
    }
}
