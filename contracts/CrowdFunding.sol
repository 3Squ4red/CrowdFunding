// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**
 * A consensus-based crowd-fund contract, capable of handling multiple creators, each with multiple 'projects'.
 *
 * Every project will have following fields: Title, Description, Minimum contribution, Target amount, Raised amount, Target reached, Contributions and Spend requests. The creator will have to provide the first 4 fields while creating a project.
 *
 * Anyone, besides the project creator can contribute to a project - for which they'd need the project creators' address and the project index.
 * While contributing, if on adding the contribution amount, the raised amount exceeds the target amount of that project, that contributor will get a refund. In other words, at no point in time, the raised amount of a project will exceed it's target amount.
 *
 * After contributing to a project, a contributor will also be allowed to withdraw his money back IF the project has not met it's target yet.
 *
 * ONLY after the target of a project is reached, it's creator will be allowed to request for funds. Each of those requests will have: Amount, Receiver, Purpose, Approvers, Spent (a boolean value showing if this request is completed).
 * The contributors will then decide whether to approve such a spending request or not. Only the requests which have MORE than 50% of the contributors' approval, will be 'spent' by the project's creator.
 *
 * By NOT directly transfering the contributions to the project creator and asking for the contributor's approval before spending their money, fraud cases could be prevented to some extent.
 */

struct SpendRequest {
    // This struct will be used by the project owners ONLY, while spending the money they raised
    uint256 amount; // Should be less than the raised amount
    address receiver;
    string purpose;
    // Above three values must be set by the project owner
    address[] approvers;
    bool spent;
}

struct Contribution {
    address contributor;
    uint256 amount;
    uint256 time; // Records the time of contribution
}

struct Project {
    // Following four values must be provided by Project creator/owner while creating a project
    bytes title;
    bytes description;
    uint256 minContribution; // Minimum amount that must be contributed to a project
    uint256 targetAmount;
    uint256 raisedAmount; // Total amount raised by this project
    bool targetReached;
    Contribution[] contributions; // This will record every individual's personal contributions
    SpendRequest[] spendRequests; // This will hold all the spending requests created by the owner
}

// Errors
// Creating a new project
error InvalidTitle();
error InvalidDescription();
error InvalidMinContribution();
error InvalidTarget();
// Zero error
error ZeroAddress();
// Contributing to a project
error InsufficientContribution(uint256 minContribution);
error SelfContribution();
// Creating a new spending request
error Overspend(uint256 raisedAmount);
error EmptyRequestPurpose();
// Approving a spending request
error FundsAlreadySpent();
error NotAContributor();
error AlreadyApproved();
// Spending funds
error UnapprovedRequest();
// Withdrawing funds
error TargetReached();
error AlreadyWithdrawn();

contract CrowdFunding {
    Project private defaultProject; // Used for project initialization
    mapping(address => Project[]) private projects;
    mapping(address => bool) private created;
    address[] public projectCreators;

    modifier validAddress(address creator) {
        if (creator == address(0)) revert ZeroAddress();
        _;
    }

    function createProject(
        string calldata _title,
        string calldata _description,
        uint256 minContribution,
        uint256 targetAmount
    ) external {
        bytes memory title = bytes(_title);
        bytes memory description = bytes(_description);
        // Validating the params
        if (title.length == 0) revert InvalidTitle();
        if (description.length == 0) revert InvalidDescription();
        if (minContribution == 0) revert InvalidMinContribution();
        if (targetAmount == 0) revert InvalidTarget();

        // If all the data are valid then simply 'push' a new project
        defaultProject.title = title;
        defaultProject.description = description;
        defaultProject.minContribution = minContribution;
        defaultProject.targetAmount = targetAmount;
        projects[msg.sender].push(defaultProject);

        // Record the creator's address if this is the first project he created
        if (!created[msg.sender]) {
            projectCreators.push(msg.sender);
            created[msg.sender] = true;
        }
    }

    function contribute(
        address creator,
        uint256 index
    ) external payable validAddress(creator) {
        if (msg.sender == creator) revert SelfContribution();

        // Get the project to which msg.sender wants to contribute
        Project storage project = projects[creator][index];

        // Revert if target already met
        require(!project.targetReached, "target met");

        // Validate contribution amount
        uint256 minC = project.minContribution;
        if (msg.value < minC) revert InsufficientContribution(minC);

        // Return back extra money if the target is met
        uint256 raised = project.raisedAmount;
        uint256 target = project.targetAmount;
        uint256 newRaised = msg.value + raised;
        uint256 contributedAmt = msg.value;
        uint256 extraMoney;
        if (newRaised >= target) {
            // Target is reached
            project.targetReached = true;
            if (newRaised > target) {
                // Store the extra money
                extraMoney = newRaised - target;
                contributedAmt = msg.value - extraMoney;
            }
        }

        // Update the project's raised amount
        project.raisedAmount += contributedAmt;

        // If msg.sender has already contributed then add msg.value to his contribution
        //      Otherwise, push his contribution details
        int256 i = alreadyContributed(msg.sender, project.contributions);
        if (i == -1)
            // Not already contributed
            project.contributions.push(
                Contribution(msg.sender, contributedAmt, block.timestamp)
            );
        else project.contributions[uint256(i)].amount += contributedAmt;

        // Return back if some extra money was sent
        if (extraMoney > 0) payable(msg.sender).transfer(extraMoney);
    }

    // This function will revert if the msg.sender has no project @index
    //      So, no need to explicitly validate index
    function requestFunds(
        uint256 index,
        uint256 amount,
        address receiver,
        string calldata purpose
    ) external validAddress(receiver) {
        // Validating purpose
        if (bytes(purpose).length == 0) revert EmptyRequestPurpose();

        Project storage project = projects[msg.sender][index];

        // Revert if the target is not yet reached
        require(project.targetReached, "target not met");
        // Validating amount
        uint256 raised = project.raisedAmount;
        if (amount > raised) revert Overspend(raised);

        project.spendRequests.push(
            SpendRequest(
                amount,
                receiver,
                purpose,
                new address[](0), // No of approvals
                false // Spent or not
            )
        );
    }

    function approve(
        address creator,
        uint256 projectIndex,
        uint256 requestIndex
    ) external validAddress(creator) {
        // Self approval is not allowed
        require(msg.sender != creator, "self approval not allowed");

        Project storage project = projects[creator][projectIndex];
        SpendRequest storage request = project.spendRequests[requestIndex];

        // Revert if the request is already spent
        if (request.spent) revert FundsAlreadySpent();
        // Revert if msg.sender is not a contributor to this project
        if (!isContributor(msg.sender, project.contributions))
            revert NotAContributor();
        // Revert if msg.sender has already approved this request once
        if (alreadyApproved(msg.sender, request.approvers))
            revert AlreadyApproved();

        request.approvers.push(msg.sender);
    }

    // This function will revert if msg.sender has no project @index
    // Or when no request exists at @requestIndex
    function spendFunds(uint256 projectIndex, uint256 requestIndex) external {
        Project storage project = projects[msg.sender][projectIndex];
        SpendRequest storage request = project.spendRequests[requestIndex];

        // Revert if the funds are already spent
        if (request.spent) revert FundsAlreadySpent();
        // Revert if the project doesn't have enough raised amount
        uint256 raised = project.raisedAmount;
        if (raised < request.amount) revert Overspend(raised);
        // Revert if the request doesn't have more than 50% approval
        if (request.approvers.length <= project.contributions.length / 2)
            revert UnapprovedRequest();

        request.spent = true;
        project.raisedAmount -= request.amount;

        // Finally transfer the amount to the receiver
        payable(request.receiver).transfer(request.amount);
    }

    function withdrawContribution(
        address creator,
        uint256 index
    ) external validAddress(creator) {
        Project storage project = projects[creator][index];

        // Revert if the target is reached
        if (project.targetReached) revert TargetReached();

        int256 i = alreadyContributed(msg.sender, project.contributions);
        if (i == -1)
            // Revert if msg.sender is not a contributor to this project
            revert NotAContributor();
        else {
            Contribution storage contribution = project.contributions[
                uint256(i)
            ];
            // "There's a bug if an AssertionError happens here
            //      Raised amount should be >= an individual's contribution"
            uint256 amount = contribution.amount;
            assert(project.raisedAmount >= amount);

            // Revert if the funds are already withdrawn
            if (amount == 0) revert AlreadyWithdrawn();

            // Update values
            contribution.amount = 0;
            project.raisedAmount -= amount;

            // Finally send ethers back
            payable(msg.sender).transfer(amount);
        }
    }

    function getProjectDetails(
        address creator,
        uint256 index
    )
        external
        view
        validAddress(creator)
        returns (
            string memory title,
            string memory description,
            uint256 min,
            uint256 target,
            uint256 raised,
            bool targetReached,
            Contribution[] memory contributions,
            SpendRequest[] memory spendRequests
        )
    {
        Project memory project = projects[creator][index];
        return (
            string(project.title),
            string(project.description),
            project.minContribution,
            project.targetAmount,
            project.raisedAmount,
            project.targetReached,
            project.contributions,
            project.spendRequests
        );
    }

    function alreadyContributed(
        address contributor,
        Contribution[] memory contributions
    ) private pure returns (int256) {
        // Can be modified to use binary search
        for (uint256 i = 0; i < contributions.length; i++) {
            if (contributions[i].contributor == contributor) return int256(i);
        }
        return -1;
    }

    function alreadyApproved(
        address approver,
        address[] memory approvers
    ) private pure returns (bool) {
        // Can be modified to use binary search
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] == approver) return true;
        }
        return false;
    }

    function isContributor(
        address contributor,
        Contribution[] memory contributions
    ) private pure returns (bool) {
        return alreadyContributed(contributor, contributions) != -1;
    }
}
